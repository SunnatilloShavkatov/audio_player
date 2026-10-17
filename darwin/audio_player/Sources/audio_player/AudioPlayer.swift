import AVFoundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

private let treadmillSize = 2
private let errorAbort = 10_000_000

private enum ProcessingState: Int {
    case idle
    case loading
    case buffering
    case ready
    case completed
}

private enum LoopMode: Int {
    case off
    case one
    case all
}

private enum PlayerError: Error {
    case invalidSource
    case unknownSourceType
    case invalidIndex
    case invalidArgument
}

// TODO: Check for and report invalid state transitions.
// TODO: Apply Apple's guidance on seeking: https://developer.apple.com/library/archive/qa/qa1820/_index.html
final class AudioPlayer: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: BetterEventChannel
    private let dataEventChannel: BetterEventChannel
    private let playerId: String
    private let loadControl: LoadControl

    private(set) var player: AVQueuePlayer?
    private(set) var speed: Float = 1.0

    private var audioSource: AudioSource?
    private var indexedAudioSources: [IndexedAudioSource] = []
    private var order: [Int] = []
    private var orderInv: [Int] = []
    private var index = 0
    private var processingState = ProcessingState.idle
    private var loopMode = LoopMode.off
    private var shuffleModeEnabled = false
    private var updateTime = 0
    private var updatePositionMs = 0
    private var bufferedPosition = 0
    // Set when the current item hasn't been played yet so we aren't sure whether sufficient audio has been buffered.
    private var bufferUnconfirmed = false
    private var seekPos = CMTime.invalid
    private var loadResult: FlutterResult?
    private var playResult: FlutterResult?
    private var automaticallyWaitsToMinimizeStalling = true
    private var allowsExternalPlayback = false
    private var playing = false
    private var volume: Float = 1.0
    private var justAdvanced = false
    private var enqueuedAll = false
    private var icyMetadata: [String: Any] = [:]
    private var errorCode: Int?
    private var errorMessage: String?
    // Items whose KVO and notification observers are currently registered.
    private let observedItems = NSHashTable<AVPlayerItem>.weakObjects()

    init(registrar: FlutterPluginRegistrar, playerId: String, loadConfiguration: [String: Any]?) {
        self.playerId = playerId
        let messenger = registrar.binaryMessenger
        methodChannel = FlutterMethodChannel(name: "uz.plugin.audio_player.methods.\(playerId)", binaryMessenger: messenger)
        eventChannel = BetterEventChannel(name: "uz.plugin.audio_player.events.\(playerId)", messenger: messenger)
        dataEventChannel = BetterEventChannel(name: "uz.plugin.audio_player.data.\(playerId)", messenger: messenger)

        loadControl = LoadControl()
        super.init()

        if let map = loadConfiguration?["darwinLoadControl"] as? [String: Any] {
            loadControl.preferredForwardBufferDuration = (map["preferredForwardBufferDuration"] as? NSNumber)?.int64Value
            loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused = (map["canUseNetworkResourcesForLiveStreamingWhilePaused"] as? NSNumber)?.boolValue ?? false
            loadControl.preferredPeakBitRate = (map["preferredPeakBitRate"] as? NSNumber)?.doubleValue
            automaticallyWaitsToMinimizeStalling = (map["automaticallyWaitsToMinimizeStalling"] as? NSNumber)?.boolValue ?? false
        }

        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    // MARK: - Method channel

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let request = call.arguments as? [String: Any] ?? [:]
        let empty = [String: Any]()
        do {
            switch call.method {
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
                let position = Self.time(fromMicroseconds: request["position"]) ?? .positiveInfinity
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
                result(FlutterMethodNotImplemented)
            }
        } catch {
            result(FlutterError(code: "error", message: "Error in \(call.method): \(error.localizedDescription)", details: "\(error)"))
        }
    }

    private static func time(fromMicroseconds value: Any?) -> CMTime? {
        (value as? NSNumber).map { CMTime(value: $0.int64Value, timescale: 1_000_000) }
    }

    /// Converts a time to whole milliseconds, mapping non-numeric times to 0.
    private static func milliseconds(of time: CMTime) -> Int {
        let seconds = CMTimeGetSeconds(time)
        if seconds.isNaN { return 0 }
        return Int(max(Double(Int32.min), min(Double(Int32.max), 1000 * seconds)))
    }

    private static let icyMetadataIdentifiers = ["icy/StreamTitle", "icy/StreamUrl"]

    private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000.0)
    }

    // MARK: - Concatenation

    // Untested
    private func concatenatingInsertAll(catId: String, index: Int, sources: [[String: Any]], shuffleOrder: [Int]) throws {
        guard let audioSource, let player else { return }
        // Find all duplicates of the identified ConcatenatingAudioSource.
        var matches: [AudioSource] = []
        audioSource.findById(catId, matches: &matches)
        // Add each new source to each match.
        for case let catSource as ConcatenatingAudioSource in matches {
            let idx = index >= 0 ? index : catSource.count
            let newSources = try decodeAudioSources(sources)
            for (j, newSource) in newSources.enumerated() {
                catSource.insertSource(newSource, at: idx + j)
            }
            catSource.setShuffleOrder(shuffleOrder)
        }
        // Index the new audio sources.
        indexedAudioSources = []
        audioSource.buildSequence(&indexedAudioSources, treeIndex: 0)
        for source in indexedAudioSources where !source.isAttached {
            source.playerItem?.audioSource = source
            addItemObservers(source.playerItem)
        }
        updateOrder()
        if let currentItem = player.currentItem as? IndexedPlayerItem {
            self.index = indexForItem(currentItem)
        } else {
            self.index = 0
        }
        enqueueFrom(self.index)
        // Notify each new IndexedAudioSource that it's been attached to the player.
        for source in indexedAudioSources where !source.isAttached {
            source.attach(player, initialPos: .invalid)
        }
        broadcastPlaybackEvent()
    }

    // Untested
    private func concatenatingRemoveRange(catId: String, start: Int, end: Int, shuffleOrder: [Int]) {
        guard let audioSource else { return }
        // Find all duplicates of the identified ConcatenatingAudioSource.
        var matches: [AudioSource] = []
        audioSource.findById(catId, matches: &matches)
        // Remove range from each match.
        for case let catSource as ConcatenatingAudioSource in matches {
            let endIndex = end >= 0 ? end : catSource.count
            catSource.removeSources(from: start, to: endIndex)
            catSource.setShuffleOrder(shuffleOrder)
        }
        // Re-index the remaining audio sources.
        let oldIndexedAudioSources = indexedAudioSources
        indexedAudioSources = []
        audioSource.buildSequence(&indexedAudioSources, treeIndex: 0)
        var j = 0
        func dropOldSource(at j: Int) {
            removeItemObservers(oldIndexedAudioSources[j].playerItem)
            removeItemObservers(oldIndexedAudioSources[j].playerItem2)
            if j < index {
                index -= 1
            }
            // Otherwise, if j == index, the currently playing item was removed.
        }
        for source in indexedAudioSources {
            while j < oldIndexedAudioSources.count && source !== oldIndexedAudioSources[j] {
                dropOldSource(at: j)
                j += 1
            }
            j += 1
        }
        // Sources removed from the end of the list.
        while j < oldIndexedAudioSources.count {
            dropOldSource(at: j)
            j += 1
        }
        updateOrder()
        if index >= indexedAudioSources.count { index = indexedAudioSources.count - 1 }
        if index < 0 { index = 0 }
        enqueueFrom(index)
        broadcastPlaybackEvent()
    }

    // Untested
    private func concatenatingMove(catId: String, currentIndex: Int, newIndex: Int, shuffleOrder: [Int]) {
        guard let audioSource else { return }
        // Find all duplicates of the identified ConcatenatingAudioSource.
        var matches: [AudioSource] = []
        audioSource.findById(catId, matches: &matches)
        // Move range within each match.
        for case let catSource as ConcatenatingAudioSource in matches {
            catSource.moveSource(from: currentIndex, to: newIndex)
            catSource.setShuffleOrder(shuffleOrder)
        }
        // Re-index the audio sources.
        indexedAudioSources = []
        audioSource.buildSequence(&indexedAudioSources, treeIndex: 0)
        updateOrder()
        enqueueFrom(indexForItem(player?.currentItem as? IndexedPlayerItem))
        broadcastPlaybackEvent()
    }

    // MARK: - Buffering state

    private func enterBuffering(_ reason: String) {
        if processingState != .idle {
            processingState = .buffering
        }
    }

    private func leaveBuffering(_ reason: String) {
        if processingState == .buffering || processingState == .loading {
            processingState = .ready
        }
    }

    // MARK: - Playback events

    private func broadcastPlaybackEvent() {
        eventChannel.sendEvent([
            "processingState": processingState.rawValue,
            "updatePosition": 1000 * updatePositionMs,
            "updateTime": updateTime,
            "bufferedPosition": 1000 * getBufferedPosition(),
            "icyMetadata": icyMetadata,
            "duration": getDurationMicroseconds(),
            "currentIndex": index,
            "errorCode": errorCode.map { $0 as Any } ?? NSNull(),
            "errorMessage": errorMessage.map { $0 as Any } ?? NSNull(),
        ] as [String: Any])
    }

    private var currentSource: IndexedAudioSource? {
        indexedAudioSources.indices.contains(index) ? indexedAudioSources[index] : nil
    }

    private func getCurrentPosition() -> Int {
        // XXX: During load, the second case will be selected returning 0.
        // TODO: Provide a similar case as seekPos for _initialPos.
        if seekPos.isValid {
            return Self.milliseconds(of: seekPos)
        } else if let source = currentSource {
            return max(0, Self.milliseconds(of: source.position))
        } else {
            return 0
        }
    }

    private func getBufferedPosition() -> Int {
        if processingState == .idle || processingState == .loading {
            return 0
        } else if let source = currentSource {
            return max(0, Self.milliseconds(of: source.bufferedPosition))
        } else {
            return 0
        }
    }

    private func getDuration() -> Int {
        if processingState == .idle || processingState == .loading {
            return -1
        } else if let source = currentSource {
            let duration = source.duration
            // Live streams (and items still loading) have an indefinite duration, reported as unknown.
            guard duration.isNumeric else { return -1 }
            return Self.milliseconds(of: duration)
        } else {
            return 0
        }
    }

    private func getDurationMicroseconds() -> Int {
        let duration = getDuration()
        return duration < 0 ? -1 : 1000 * duration
    }

    // MARK: - Item observers

    private func removeItemObservers(_ playerItem: AVPlayerItem?) {
        guard let playerItem, observedItems.contains(playerItem) else { return }
        observedItems.remove(playerItem)
        playerItem.removeObserver(self, forKeyPath: "status")
        playerItem.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        playerItem.removeObserver(self, forKeyPath: "playbackBufferFull")
        playerItem.removeObserver(self, forKeyPath: "loadedTimeRanges")
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    }

    private func addItemObservers(_ playerItem: AVPlayerItem?) {
        guard let playerItem, !observedItems.contains(playerItem) else { return }
        observedItems.add(playerItem)
        // Get notified when the item is loaded or had an error loading
        playerItem.addObserver(self, forKeyPath: "status", options: .new, context: nil)
        // Get notified of the buffer state
        playerItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: "playbackBufferFull", options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
        // Get notified when playback has reached the end
        NotificationCenter.default.addObserver(self, selector: #selector(onComplete(_:)), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

        // Only ask for the ICY identifiers that metadataOutput(_:didOutputTimedMetadataGroups:from:)
        // reads, so other timed metadata is never delivered to the main queue.
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: Self.icyMetadataIdentifiers)
        metadataOutput.setDelegate(self, queue: .main)
        // The delegate is stored as a weak reference, so there is no retain cycle.
        // The output is owned by the item and released with it, so there is no
        // need to call removeOutput later.
        playerItem.add(metadataOutput)
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        // ICY headers aren't available here; only the timed metadata is.
        var hasIcyData = false
        var title: String?
        var url: String?
        for group in groups {
            for item in group.items {
                switch item.identifier?.rawValue {
                case "icy/StreamTitle":
                    hasIcyData = true
                    title = item.value as? String
                case "icy/StreamUrl":
                    hasIcyData = true
                    url = item.value as? String
                default:
                    break
                }
            }
        }
        if hasIcyData {
            icyMetadata = [
                "info": [
                    "title": title.map { $0 as Any } ?? NSNull(),
                    "url": url.map { $0 as Any } ?? NSNull(),
                ] as [String: Any],
            ]
            broadcastPlaybackEvent()
        }
    }

    // MARK: - Audio source decoding

    private func decodeAudioSources(_ data: [[String: Any]]) throws -> [AudioSource] {
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

    // MARK: - Queue management

    private func enqueueFrom(_ newIndex: Int) {
        index = newIndex

        guard let player else { return }

        // Update the queue while keeping the currently playing item untouched.

        // First, remove all player items except for the currently playing one (if any).
        let oldItem = player.currentItem as? IndexedPlayerItem
        var existingItem: IndexedPlayerItem?
        let newItem = currentSource?.playerItem
        // In the first pass, preserve the old and new items.
        // TODO: preserve as much of the treadmill as possible
        for item in player.items() {
            if item === newItem {
                // Preserve and tag new item if it is already in the queue.
                existingItem = item as? IndexedPlayerItem
            } else if item === oldItem {
                // Temporarily preserve old item, just to avoid jumping to
                // intermediate queue positions unnecessarily. We only want to jump
                // once to the new index.
            } else {
                player.remove(item)
            }
        }
        // In the second pass, remove the old item (if different from new item).
        if let oldItem, newItem !== oldItem {
            player.remove(oldItem)
        }

        // Regenerate queue
        enqueuedAll = false
        if existingItem == nil || loopMode != .one {
            enqueuedAll = true
            var include = false
            for si in order where indexedAudioSources.indices.contains(si) {
                if si == index { include = true }
                let source = indexedAudioSources[si]
                if include, let item = source.playerItem, item !== existingItem {
                    if source.lazyLoading && player.items().count >= treadmillSize {
                        // Enqueue up until the first lazy item that does not fit on the treadmill.
                        enqueuedAll = false
                        break
                    }
                    player.insert(item, after: nil)
                    if loopMode == .one {
                        // We only want one item in the queue.
                        break
                    }
                }
            }
        }

        // Add next loop item if we're looping
        if let first = order.first {
            if loopMode == .all && enqueuedAll, indexedAudioSources.indices.contains(first) {
                insertLoopItem(of: indexedAudioSources[first], into: player)
            } else if loopMode == .one, let source = currentSource {
                insertLoopItem(of: source, into: player)
            }
        }

        if processingState != .loading && oldItem !== newItem {
            if player.currentItem?.isPlaybackBufferEmpty == true {
                enterBuffering("enqueueFrom playbackBufferEmpty")
            } else {
                leaveBuffering("enqueueFrom !playbackBufferEmpty")
            }
            updatePosition()
        }

        updateEndAction()
    }

    private func insertLoopItem(of source: IndexedAudioSource, into player: AVQueuePlayer) {
        if source.playerItem2 == nil {
            source.preparePlayerItem2()
            addItemObservers(source.playerItem2)
        }
        if let item = source.playerItem2 {
            player.insert(item, after: nil)
        }
    }

    private func updatePosition() {
        updatePositionMs = getCurrentPosition()
        updateTime = Self.nowMilliseconds()
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
        return clipper
    }

    private func load(_ source: [String: Any], initialPosition: CMTime, initialIndex: Int?, result: @escaping FlutterResult) throws {
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
            previousLoadResult(FlutterError(code: "\(errorAbort)", message: "Connection aborted", details: nil))
        }
        loadResult = result
        processingState = .loading
        index = initialIndex ?? 0
        errorCode = nil
        errorMessage = nil
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
            loadResult?(["duration": getDurationMicroseconds()])
            loadResult = nil
        } else {
            // We send result after the playerItem is ready in observeValue.
        }
    }

    private func updateOrder() {
        orderInv = Array(repeating: 0, count: indexedAudioSources.count)
        if shuffleModeEnabled {
            order = audioSource?.getShuffleIndices() ?? []
        } else {
            order = Array(indexedAudioSources.indices)
        }
        for (i, si) in order.enumerated() where orderInv.indices.contains(si) {
            orderInv[si] = i
        }
    }

    /// The position of the source at `index` within the (possibly shuffled) play order.
    private func orderPosition(of index: Int) -> Int {
        orderInv.indices.contains(index) ? orderInv[index] : 0
    }

    // MARK: - Notifications

    @objc private func onComplete(_ notification: Notification) {
        guard let endedPlayerItem = notification.object as? IndexedPlayerItem else { return }
        let endedSource = endedPlayerItem.audioSource

        if loopMode == .one {
            endedSource?.seek(.zero)
            justAdvanced = true
        } else if loopMode == .all, !order.isEmpty {
            endedSource?.seek(.zero)
            index = order[(orderPosition(of: index) + 1) % order.count]
            broadcastPlaybackEvent()
            justAdvanced = true
        } else if orderPosition(of: index) + 1 < order.count {
            endedSource?.seek(.zero)
            index = order[orderPosition(of: index) + 1]
            updateEndAction()
            broadcastPlaybackEvent()
            justAdvanced = true
        } else {
            // reached end of playlist
            complete()
        }
    }

    // MARK: - Key-value observing

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case "status":
            guard let playerItem = object as? IndexedPlayerItem else { return }
            let status = (change?[.newKey] as? NSNumber).flatMap { AVPlayerItem.Status(rawValue: $0.intValue) } ?? .unknown
            playerItem.audioSource?.onStatusChanged(status)
            switch status {
            case .readyToPlay:
                guard let player, playerItem === player.currentItem else { return }
                // Detect buffering in different ways depending on whether we're playing
                if playing {
                    if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                        enterBuffering("ready to play: playing, waitingToPlay")
                    } else {
                        leaveBuffering("ready to play: playing, !waitingToPlay")
                    }
                } else {
                    if player.currentItem?.isPlaybackBufferEmpty == true {
                        enterBuffering("ready to play: !playing, playbackBufferEmpty")
                    } else {
                        leaveBuffering("ready to play: !playing, !playbackBufferEmpty")
                    }
                }
                updatePosition()
                broadcastPlaybackEvent()
                if let loadResult {
                    loadResult(["duration": getDurationMicroseconds()])
                    self.loadResult = nil
                }
            case .failed:
                if playerItem === player?.currentItem {
                    sendErrorForItem(playerItem)
                }
            case .unknown:
                break
            @unknown default:
                break
            }
        case "playbackBufferEmpty", "playbackBufferFull":
            // Use these values to detect buffering.
            guard let playerItem = object as? IndexedPlayerItem, playerItem === player?.currentItem else { return }
            // If there's a seek in progress, these values are unreliable
            if seekPos.isValid { return }
            // When playing, buffering is handled with timeControlStatus instead.
            if !playing {
                if playerItem.isPlaybackBufferEmpty {
                    enterBuffering("!playing, playbackBufferEmpty")
                } else {
                    leaveBuffering("!playing, !playbackBufferEmpty || playbackBufferFull")
                }
                updatePosition()
                broadcastPlaybackEvent()
            }
        case "timeControlStatus":
            guard let player else { return }
            switch player.timeControlStatus {
            case .paused:
                break
            case .waitingToPlayAtSpecifiedRate:
                if processingState != .completed {
                    enterBuffering("timeControlStatus")
                    updatePosition()
                    broadcastPlaybackEvent()
                } else {
                    // Ignoring wait signal because we reached the end
                }
            case .playing:
                leaveBuffering("timeControlStatus")
                updatePosition()
                broadcastPlaybackEvent()
            @unknown default:
                break
            }
        case "currentItem" where player?.currentItem != nil:
            guard let playerItem = change?[.newKey] as? IndexedPlayerItem else { return }
            if playerItem.status == .failed {
                sendErrorForItem(playerItem)
                return
            } else {
                let expectedIndex = indexForItem(playerItem)
                if index != expectedIndex {
                    // AVQueuePlayer will sometimes skip over error items without
                    // notifying this observer.
                    index = expectedIndex
                    updateEndAction()
                    broadcastPlaybackEvent()
                }
            }
            bufferUnconfirmed = true

            if justAdvanced {
                let audioSource = playerItem.audioSource
                if loopMode == .one {
                    audioSource?.flip()
                    enqueueFrom(index)
                } else if loopMode == .all {
                    if index == order.first && playerItem === audioSource?.playerItem2 {
                        audioSource?.flip()
                        enqueueFrom(index)
                    } else if !enqueuedAll {
                        enqueueFrom(index)
                    } else {
                        updateEndAction()
                    }
                } else if !enqueuedAll {
                    enqueueFrom(index)
                }
                justAdvanced = false
            }
        case "loadedTimeRanges":
            guard let playerItem = object as? IndexedPlayerItem, playerItem === player?.currentItem else { return }
            let pos = getBufferedPosition()
            if pos != bufferedPosition {
                bufferedPosition = pos
                broadcastPlaybackEvent()
            }
        default:
            break
        }
    }

    // MARK: - Errors

    private func sendErrorForItem(_ playerItem: IndexedPlayerItem) {
        let error = playerItem.error as NSError?
        sendError(error?.code ?? 0, errorMessage: playerItem.error?.localizedDescription, playerItem: playerItem, switchToIdle: true)
        player?.removeAllItems()
    }

    private func sendError(_ errorCode: Int, errorMessage: String?, playerItem: IndexedPlayerItem?, switchToIdle: Bool) {
        let flutterError = FlutterError(
            code: "\(errorCode)",
            message: errorMessage,
            details: playerItem.map { ["index": indexForItem($0)] }
        )
        eventChannel.sendEvent(flutterError)
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        if switchToIdle {
            processingState = .idle
        }
        broadcastPlaybackEvent()
        if let loadResult, playerItem === player?.currentItem {
            loadResult(flutterError)
            self.loadResult = nil
        }
    }

    private func abortExistingConnection(switchToIdle: Bool) {
        sendError(errorAbort, errorMessage: "Connection aborted", playerItem: nil, switchToIdle: switchToIdle)
    }

    private func indexForItem(_ playerItem: IndexedPlayerItem?) -> Int {
        guard let playerItem else { return -1 }
        return indexedAudioSources.firstIndex { $0.playerItem === playerItem || $0.playerItem2 === playerItem } ?? -1
    }

    // MARK: - Playback control

    private func play(result: @escaping FlutterResult) {
        if playing {
            result([String: Any]())
            return
        }
        if let playResult {
            playResult([String: Any]())
        }
        playResult = result
        playing = true
        player?.rate = speed
        updatePosition()
    }

    private func pause() {
        if !playing { return }
        playing = false
        player?.pause()
        updatePosition()
        broadcastPlaybackEvent()
        if let playResult {
            playResult([String: Any]())
            self.playResult = nil
        }
    }

    private func complete() {
        updatePosition()
        processingState = .completed
        broadcastPlaybackEvent()
        if let playResult {
            playResult([String: Any]())
            self.playResult = nil
        }
    }

    private func setVolume(_ volume: Float) {
        self.volume = volume
        player?.volume = volume
    }

    private func setSpeed(_ speed: Float) {
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

    private func setLoopMode(_ rawLoopMode: Int) {
        let newLoopMode = LoopMode(rawValue: rawLoopMode) ?? .off
        if newLoopMode == loopMode { return }
        loopMode = newLoopMode
        enqueueFrom(index)
    }

    private func updateEndAction() {
        // Should be called in the following situations:
        // - when the audio source changes
        // - when index changes
        // - when the loop mode changes.
        // - when the shuffle order changes. (TODO)
        // - when the shuffle mode changes.
        guard let player else { return }
        if audioSource != nil && (loopMode != .off || (!order.isEmpty && orderPosition(of: index) + 1 < order.count)) {
            player.actionAtItemEnd = .advance
        } else {
            player.actionAtItemEnd = .pause // .none
        }
    }

    private func setShuffleModeEnabled(_ enabled: Bool) {
        shuffleModeEnabled = enabled
        if audioSource == nil { return }

        updateOrder()

        enqueueFrom(index)
    }

    private func setShuffleOrder(_ dict: [String: Any]) {
        guard let audioSource else { return }

        audioSource.decodeShuffleOrder(dict)

        updateOrder()

        enqueueFrom(index)
    }

    private func setAutomaticallyWaitsToMinimizeStalling(_ enabled: Bool) {
        automaticallyWaitsToMinimizeStalling = enabled
        player?.automaticallyWaitsToMinimizeStalling = enabled
    }

    private func setCanUseNetworkResourcesForLiveStreamingWhilePaused(_ enabled: Bool) {
        loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused = enabled
        for source in indexedAudioSources {
            source.applyCanUseNetworkResourcesForLiveStreamingWhilePaused()
        }
    }

    private func setPreferredPeakBitRate(_ preferredPeakBitRate: Double?) {
        loadControl.preferredPeakBitRate = preferredPeakBitRate
        for source in indexedAudioSources {
            source.applyPreferredPeakBitRate()
        }
    }

    private func setAllowsExternalPlayback(_ enabled: Bool) {
        allowsExternalPlayback = enabled
        player?.allowsExternalPlayback = enabled
    }

    private func seek(_ position: CMTime, index newIndex: Int?, completionHandler: @escaping (Bool) -> Void) throws {
        if processingState == .idle || processingState == .loading {
            completionHandler(false)
            return
        }
        let targetIndex = newIndex ?? index
        guard indexedAudioSources.indices.contains(targetIndex), let currentSource else {
            throw PlayerError.invalidIndex
        }
        if targetIndex != index {
            // Jump to a distant item
            if playing {
                player?.pause()
            }
            currentSource.seek(.zero)
            // The "currentItem" key observer will respect that a seek is already in progress
            seekPos = position
            updatePosition()
            enqueueFrom(targetIndex)
            let source = indexedAudioSources[index]
            if abs(Self.milliseconds(of: CMTimeSubtract(source.position, position))) > 100 {
                enterBuffering("seek to index")
                updatePosition()
                broadcastPlaybackEvent()
                source.seek(position) { finished in
                    if !self.playing {
                        // When playing, this is handled by timeControlStatus.
                        if self.bufferUnconfirmed && self.player?.currentItem?.isPlaybackBufferFull != true {
                            // Stay in buffering
                        } else if source.playerItem?.status == .readyToPlay {
                            self.leaveBuffering("seek to index finished, (!bufferUnconfirmed || playbackBufferFull) && ready to play")
                            self.updatePosition()
                            self.broadcastPlaybackEvent()
                        }
                    }
                    if self.playing {
                        self.player?.rate = self.speed
                    }
                    self.seekPos = .invalid
                    self.broadcastPlaybackEvent()
                    completionHandler(finished)
                }
            } else {
                seekPos = .invalid
                if playing {
                    // NOTE: Re-enable playImmediately(atRate:) only after figuring out
                    // how to detect buffering when buffered audio is not
                    // immediately available.
                    player?.rate = speed
                }
                broadcastPlaybackEvent()
                completionHandler(true)
            }
        } else {
            // Seek within an item
            if playing {
                player?.pause()
            }
            seekPos = position
            // TODO: Move this into a separate method so it can also
            // be used in skip.
            enterBuffering("seek")
            updatePosition()
            broadcastPlaybackEvent()
            currentSource.seek(position) { finished in
                self.updatePosition()
                if self.playing {
                    // If playing, buffering will be detected by timeControlStatus.
                    // NOTE: Re-enable playImmediately(atRate:) only after figuring out
                    // how to detect buffering when buffered audio is not immediately
                    // available.
                    self.player?.rate = self.speed
                } else {
                    // If not playing, there is no reliable way to detect
                    // when buffering has completed, so we use
                    // !playbackBufferEmpty. Although this always seems to
                    // be full even right after a seek.
                    if self.player?.currentItem?.isPlaybackBufferEmpty == true {
                        self.enterBuffering("seek finished, playbackBufferEmpty")
                    } else {
                        self.leaveBuffering("seek finished, !playbackBufferEmpty")
                    }
                    self.updatePosition()
                    if self.processingState != .buffering {
                        self.broadcastPlaybackEvent()
                    }
                }
                self.seekPos = .invalid
                self.broadcastPlaybackEvent()
                completionHandler(finished)
            }
        }
    }

    // MARK: - Disposal

    func dispose(calledFromDeinit: Bool) {
        // The player is only created by the first successful load, but the channels exist from init and must be
        // released either way.
        if let player {
            if processingState != .idle {
                player.pause()
                updatePosition()
                // If used just before destroying the current FlutterEngine, sending results in:
                // NSInternalInconsistencyException: 'Sending a message before the FlutterEngine has been run.'
                if !calledFromDeinit {
                    broadcastPlaybackEvent()
                }
                processingState = .idle
            }
            player.removeObserver(self, forKeyPath: "currentItem")
            player.removeObserver(self, forKeyPath: "timeControlStatus")
            self.player = nil
        }
        // Replying to a pending call also goes through the messenger.
        if !calledFromDeinit {
            playResult?([String: Any]())
            loadResult?(FlutterError(code: "\(errorAbort)", message: "Connection aborted", details: nil))
        }
        playResult = nil
        loadResult = nil
        for source in indexedAudioSources {
            removeItemObservers(source.playerItem)
            removeItemObservers(source.playerItem2)
        }
        indexedAudioSources = []
        audioSource = nil
        eventChannel.dispose(calledFromDeinit: calledFromDeinit)
        dataEventChannel.dispose(calledFromDeinit: calledFromDeinit)
        if !calledFromDeinit {
            methodChannel.setMethodCallHandler(nil)
        }
    }
}
