import AVFoundation

// Decoding of the audio sources sent by Dart, and loading them into the player.
extension AudioPlayer {
    // MARK: - Audio source decoding

    func decodeAudioSources(_ data: [[String: Any]]) throws -> [AudioSource] {
        try data.map { try decodeAudioSource($0) }
    }

    private func decodeAudioSource(_ data: [String: Any]) throws -> AudioSource {
        guard let type = data["type"] as? String, let id = data["id"] as? String else {
            throw PlayerError.invalidSource
        }
        switch type {
        case "progressive", "dash", "hls":
            guard let uri = data["uri"] as? String else { throw PlayerError.invalidSource }
            let headers = (data["headers"] as? [String: Any])?.compactMapValues { $0 as? String }
            return UriAudioSource(id: id, uri: uri, loadControl: loadControl, headers: headers, options: data["options"] as? [String: Any])
        case "concatenating":
            return ConcatenatingAudioSource(
                id: id,
                audioSources: try decodeAudioSources(data["children"] as? [[String: Any]] ?? []),
                shuffleOrder: data["shuffleOrder"] as? [Int] ?? [],
                lazyLoading: (data["useLazyPreparation"] as? NSNumber)?.boolValue ?? false
            )
        case "clipping":
            guard let childData = data["child"] as? [String: Any],
                  let child = try decodeAudioSource(childData) as? UriAudioSource else {
                throw PlayerError.invalidSource
            }
            return ClippingAudioSource(
                id: id,
                audioSource: child,
                start: (data["start"] as? NSNumber)?.int64Value,
                end: (data["end"] as? NSNumber)?.int64Value
            )
        default:
            throw PlayerError.unknownSourceType
        }
    }

    /// Decodes the source passed to `load`, reusing the previously loaded child when only the clip changes.
    private func decodeLoadSource(_ source: [String: Any]) throws -> AudioSource {
        guard let previousSource = audioSource, source["type"] as? String == "clipping" else {
            return try decodeAudioSource(source)
        }
        // Check if we're clipping an audio source that was previously loaded.
        var child: UriAudioSource?
        if let clipper = previousSource as? ClippingAudioSource {
            child = clipper.audioSource
        } else if let uriSource = previousSource as? UriAudioSource {
            child = uriSource
        }
        let childData = source["child"] as? [String: Any]
        var uri: String?
        if let type = childData?["type"] as? String, ["progressive", "dash", "hls"].contains(type) {
            uri = childData?["uri"] as? String
        }
        guard let child, let uri, child.uri == uri, let id = source["id"] as? String else {
            return try decodeAudioSource(source)
        }
        let clipper = ClippingAudioSource(
            id: id,
            audioSource: child,
            start: (source["start"] as? NSNumber)?.int64Value,
            end: (source["end"] as? NSNumber)?.int64Value
        )
        clipper.playerItem?.audioSource = clipper
        clipper.playerItem2?.audioSource = clipper
        if clipper.playerItem2 != nil {
            // The reused loop item still has the previous clip's end time and position.
            clipper.preparePlayerItem2()
        }
        return clipper
    }

    func load(_ source: [String: Any], initialPosition: CMTime, initialIndex: Int?, result: @escaping NativeResult) throws {
        // Decode before touching any state so that an invalid source leaves the current one intact.
        let newAudioSource = try decodeLoadSource(source)
        if playing {
            player?.pause()
        }
        if processingState == .loading {
            abortExistingConnection(switchToIdle: false)
        }
        if let previousLoadResult = loadResult {
            // The previous load was superseded before its item became ready.
            previousLoadResult(NativeError(code: "\(errorAbort)", message: "Connection aborted", details: nil))
        }
        loadResult = result
        processingState = .loading
        index = initialIndex ?? 0
        errorCode = nil
        errorMessage = nil
        // A seek from before this load is over: invalidate its completion and fail the ones still waiting for an item.
        seekGeneration += 1
        seekPos = .invalid
        for indexedSource in indexedAudioSources {
            indexedSource.cancelQueuedSeek()
        }
        // Remove previous observers
        for indexedSource in indexedAudioSources {
            removeItemObservers(indexedSource.playerItem)
            removeItemObservers(indexedSource.playerItem2)
        }
        audioSource = newAudioSource
        indexedAudioSources = []
        audioSource?.buildSequence(&indexedAudioSources, treeIndex: 0)
        for indexedSource in indexedAudioSources {
            addItemObservers(indexedSource.playerItem)
            indexedSource.playerItem?.audioSource = indexedSource
        }
        updatePosition()
        updateOrder()
        // Set up an empty player
        let player: AVQueuePlayer
        if let existingPlayer = self.player {
            player = existingPlayer
        } else {
            player = AVQueuePlayer(items: [])
            player.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
            // Removed again in dispose(calledFromDeinit:).
            player.addObserver(self, forKeyPath: "timeControlStatus", options: .new, context: nil)
            player.allowsExternalPlayback = allowsExternalPlayback
            player.addObserver(self, forKeyPath: "currentItem", options: .new, context: nil)
            self.player = player
        }
        // Initialise the AVQueuePlayer with items.
        enqueueFrom(index)
        // Notify each IndexedAudioSource that it's been attached to the player.
        for (i, indexedSource) in indexedAudioSources.enumerated() {
            indexedSource.attach(player, initialPos: i == index ? initialPosition : .invalid)
        }

        if playing {
            player.rate = speed
        }
        player.volume = volume
        broadcastPlaybackEvent()

        if loadResult != nil, indexedAudioSources.isEmpty || player.currentItem == nil || player.currentItem?.status == .readyToPlay {
            processingState = .ready
            // Dart waits for an event that isn't loading before it completes the load.
            broadcastPlaybackEvent()
            loadResult?(["duration": getDurationMicroseconds()])
            loadResult = nil
        } else {
            // We send result after the playerItem is ready in observeValue.
        }
    }
}
