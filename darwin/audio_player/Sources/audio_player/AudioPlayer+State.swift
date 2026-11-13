import AVFoundation

// Processing state, positions and errors, and the playback events that report them to Dart.
extension AudioPlayer {
    // MARK: - Buffering state

    func enterBuffering(_ reason: String) {
        if processingState != .idle {
            processingState = .buffering
        }
    }

    func leaveBuffering(_ reason: String) {
        if processingState == .buffering || processingState == .loading {
            processingState = .ready
            // Leaving buffering confirms that enough of the current item is buffered.
            bufferUnconfirmed = false
        }
    }

    // MARK: - Playback events

    func broadcastPlaybackEvent() {
        playbackEvents.sendEvent([
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

    var currentSource: IndexedAudioSource? {
        indexedAudioSources.indices.contains(index) ? indexedAudioSources[index] : nil
    }

    private func getCurrentPosition() -> Int {
        // While loading, the second case is selected and returns 0.
        if seekPos.isValid {
            return Self.milliseconds(of: seekPos)
        } else if let source = currentSource {
            return max(0, Self.milliseconds(of: source.position))
        } else {
            return 0
        }
    }

    func getBufferedPosition() -> Int {
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
            // No current source, so there is no known duration.
            return -1
        }
    }

    func getDurationMicroseconds() -> Int {
        let duration = getDuration()
        return duration < 0 ? -1 : 1000 * duration
    }

    func updatePosition() {
        updatePositionMs = getCurrentPosition()
        updateTime = Self.nowMilliseconds()
    }

    private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000.0)
    }

    // MARK: - Errors

    func sendErrorForItem(_ playerItem: IndexedPlayerItem) {
        let error = playerItem.error as NSError?
        sendError(error?.code ?? 0, errorMessage: playerItem.error?.localizedDescription, playerItem: playerItem, switchToIdle: true)
        player?.removeAllItems()
    }

    private func sendError(_ errorCode: Int, errorMessage: String?, playerItem: IndexedPlayerItem?, switchToIdle: Bool) {
        let flutterError = NativeError(
            code: "\(errorCode)",
            message: errorMessage,
            details: playerItem.map { ["index": indexForItem($0)] }
        )
        playbackEvents.sendEvent(flutterError)
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

    func abortExistingConnection(switchToIdle: Bool) {
        sendError(errorAbort, errorMessage: "Connection aborted", playerItem: nil, switchToIdle: switchToIdle)
    }
}
