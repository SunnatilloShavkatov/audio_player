import AVFoundation

// Decoding of the calls Dart makes on the player, and the setters they run.
extension AudioPlayer {
    func handleCall(_ method: String, request: [String: Any], result: @escaping NativeResult) {
        let empty = [String: Any]()
        do {
            switch method {
            case "load":
                guard let source = request["audioSource"] as? [String: Any] else { throw PlayerError.invalidSource }
                let initialPosition = Self.time(fromMicroseconds: request["initialPosition"]) ?? .invalid
                let initialIndex = (request["initialIndex"] as? NSNumber)?.intValue
                try load(source, initialPosition: initialPosition, initialIndex: initialIndex, result: result)
            case "play":
                play(result: result)
            case "pause":
                pause()
                result(empty)
            case "setVolume":
                guard let volume = (request["volume"] as? NSNumber)?.floatValue else { throw PlayerError.invalidArgument }
                setVolume(volume)
                result(empty)
            case "setSkipSilence", "setPitch":
                // Not supported by AVPlayer; accepted as a no-op so the call does not fail on iOS/macOS.
                result(empty)
            case "setSpeed":
                guard let speed = (request["speed"] as? NSNumber)?.floatValue, speed > 0 else {
                    throw PlayerError.invalidArgument
                }
                setSpeed(speed)
                result(empty)
            case "setLoopMode":
                setLoopMode((request["loopMode"] as? NSNumber)?.intValue ?? 0)
                result(empty)
            case "setShuffleMode":
                setShuffleModeEnabled((request["shuffleMode"] as? NSNumber)?.intValue == 1)
                result(empty)
            case "setShuffleOrder":
                setShuffleOrder(request["audioSource"] as? [String: Any] ?? [:])
                result(empty)
            case "setAutomaticallyWaitsToMinimizeStalling":
                setAutomaticallyWaitsToMinimizeStalling((request["enabled"] as? NSNumber)?.boolValue ?? false)
                result(empty)
            case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                setCanUseNetworkResourcesForLiveStreamingWhilePaused((request["enabled"] as? NSNumber)?.boolValue ?? false)
                result(empty)
            case "setPreferredPeakBitRate":
                setPreferredPeakBitRate((request["bitRate"] as? NSNumber)?.doubleValue)
                result(empty)
            case "setAllowsExternalPlayback":
                setAllowsExternalPlayback((request["allowsExternalPlayback"] as? NSNumber)?.intValue == 1)
                result(empty)
            case "seek":
                let position = Self.time(fromMicroseconds: request["position"])
                try seek(position, index: (request["index"] as? NSNumber)?.intValue) { _ in
                    result(empty)
                }
            case "concatenatingInsertAll":
                try concatenatingInsertAll(
                    catId: request["id"] as? String ?? "",
                    index: (request["index"] as? NSNumber)?.intValue ?? 0,
                    sources: request["children"] as? [[String: Any]] ?? [],
                    shuffleOrder: request["shuffleOrder"] as? [Int] ?? []
                )
                result(empty)
            case "concatenatingRemoveRange":
                concatenatingRemoveRange(
                    catId: request["id"] as? String ?? "",
                    start: (request["startIndex"] as? NSNumber)?.intValue ?? 0,
                    end: (request["endIndex"] as? NSNumber)?.intValue ?? 0,
                    shuffleOrder: request["shuffleOrder"] as? [Int] ?? []
                )
                result(empty)
            case "concatenatingMove":
                concatenatingMove(
                    catId: request["id"] as? String ?? "",
                    currentIndex: (request["currentIndex"] as? NSNumber)?.intValue ?? 0,
                    newIndex: (request["newIndex"] as? NSNumber)?.intValue ?? 0,
                    shuffleOrder: request["shuffleOrder"] as? [Int] ?? []
                )
                result(empty)
            case "setAndroidAudioAttributes":
                result(empty)
            default:
                result(NativeError(code: "unimplemented", message: "Unknown method \(method)", details: nil))
            }
        } catch {
            result(NativeError(code: "error", message: "Error in \(method): \(error.localizedDescription)", details: "\(error)"))
        }
    }

    private static func time(fromMicroseconds value: Any?) -> CMTime? {
        (value as? NSNumber).map { CMTime(value: $0.int64Value, timescale: 1_000_000) }
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        player?.volume = volume
    }

    func setSpeed(_ speed: Float) {
        // NOTE: We ideally should check player.currentItem.canPlaySlowForward and
        // canPlayFastForward, but these properties are unreliable and the official
        // documentation is unclear and contradictory.
        //
        // Source #1:
        // https://developer.apple.com/documentation/avfoundation/avplayer/1388846-rate?language=objc
        //
        //     Rates other than 0.0 and 1.0 can be used if the associated player
        //     item returns YES for the AVPlayerItem properties canPlaySlowForward
        //     or canPlayFastForward.
        //
        // Source #2:
        // https://developer.apple.com/library/archive/qa/qa1772/_index.html
        //
        //     An AVPlayerItem whose status property equals
        //     AVPlayerItemStatusReadyToPlay can be played at rates between 1.0 and
        //     2.0, inclusive, even if AVPlayerItem.canPlayFastForward is NO.
        //     AVPlayerItem.canPlayFastForward indicates whether the item can be
        //     played at rates greater than 2.0.
        //
        // But in practice, it appears that even if AVPlayerItem.canPlayFastForward
        // is NO, rates greater than 2.0 still work sometimes.
        //
        // So for now, we just let the app pass in any speed and hope for the best.
        // There is no way to reliably query whether the requested speed is
        // supported.
        self.speed = speed
        if playing {
            player?.rate = speed
        }
        updatePosition()
    }

    func setLoopMode(_ rawLoopMode: Int) {
        let newLoopMode = LoopMode(rawValue: rawLoopMode) ?? .off
        if newLoopMode == loopMode { return }
        loopMode = newLoopMode
        enqueueFrom(index)
    }

    func setShuffleModeEnabled(_ enabled: Bool) {
        shuffleModeEnabled = enabled
        if audioSource == nil { return }

        updateOrder()

        enqueueFrom(index)
    }

    func setShuffleOrder(_ dict: [String: Any]) {
        guard let audioSource else { return }

        audioSource.decodeShuffleOrder(dict)

        updateOrder()

        enqueueFrom(index)
    }

    func setAutomaticallyWaitsToMinimizeStalling(_ enabled: Bool) {
        automaticallyWaitsToMinimizeStalling = enabled
        player?.automaticallyWaitsToMinimizeStalling = enabled
    }

    func setCanUseNetworkResourcesForLiveStreamingWhilePaused(_ enabled: Bool) {
        loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused = enabled
        for source in indexedAudioSources {
            source.applyCanUseNetworkResourcesForLiveStreamingWhilePaused()
        }
    }

    func setPreferredPeakBitRate(_ preferredPeakBitRate: Double?) {
        loadControl.preferredPeakBitRate = preferredPeakBitRate
        for source in indexedAudioSources {
            source.applyPreferredPeakBitRate()
        }
    }

    func setAllowsExternalPlayback(_ enabled: Bool) {
        allowsExternalPlayback = enabled
        player?.allowsExternalPlayback = enabled
    }
}
