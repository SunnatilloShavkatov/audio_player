import AVFoundation

// Observers of the player items: KVO, the end of an item and the ICY metadata.
extension AudioPlayer {
    private static let icyMetadataIdentifiers = ["icy/StreamTitle", "icy/StreamUrl"]

    func removeItemObservers(_ playerItem: AVPlayerItem?) {
        guard let playerItem, observedItems.contains(playerItem) else { return }
        observedItems.remove(playerItem)
        playerItem.removeObserver(self, forKeyPath: "status")
        playerItem.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        playerItem.removeObserver(self, forKeyPath: "playbackBufferFull")
        playerItem.removeObserver(self, forKeyPath: "loadedTimeRanges")
        if let token = endObservers.removeValue(forKey: ObjectIdentifier(playerItem)) {
            NotificationCenter.default.removeObserver(token)
        }
        if let output = metadataOutputs.removeValue(forKey: ObjectIdentifier(playerItem)) {
            playerItem.remove(output)
        }
    }

    func addItemObservers(_ playerItem: AVPlayerItem?) {
        guard let playerItem, !observedItems.contains(playerItem) else { return }
        observedItems.add(playerItem)
        // Get notified when the item is loaded or had an error loading
        playerItem.addObserver(self, forKeyPath: "status", options: .new, context: nil)
        // Get notified of the buffer state
        playerItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: "playbackBufferFull", options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: .new, context: nil)
        // Get notified when playback has reached the end
        // Delivered synchronously on the posting thread, which keeps it ordered with the "currentItem" change on the
        // main thread, but handled on the main thread whatever thread AVFoundation posts from.
        endObservers[ObjectIdentifier(playerItem)] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: nil
        ) { [weak self] notification in
            if Thread.isMainThread {
                self?.onComplete(notification)
            } else {
                DispatchQueue.main.async { self?.onComplete(notification) }
            }
        }

        // Only ask for the ICY identifiers that metadataOutput(_:didOutputTimedMetadataGroups:from:)
        // reads, so other timed metadata is never delivered to the main queue.
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: Self.icyMetadataIdentifiers)
        metadataOutput.setDelegate(self, queue: .main)
        // The delegate is stored as a weak reference, so there is no retain cycle. The output is removed again in
        // removeItemObservers, so that observing an item again doesn't attach a second one (duplicate ICY events).
        playerItem.add(metadataOutput)
        metadataOutputs[ObjectIdentifier(playerItem)] = metadataOutput
    }

    private func onComplete(_ notification: Notification) {
        guard !disposed, let endedPlayerItem = notification.object as? IndexedPlayerItem else { return }
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

    /// Handles the key-value changes that `observeValue(forKeyPath:of:change:context:)` receives.
    func handleKeyValueChange(_ keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?) {
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
                // Audio is coming out, so the buffer is confirmed.
                bufferUnconfirmed = false
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
}

extension AudioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        guard !disposed else { return }
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
}
