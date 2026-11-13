import AVFoundation

// Playback control: play, pause, completion and seeking.
extension AudioPlayer {
    func play(result: @escaping NativeResult) {
        if playing {
            result([String: Any]())
            return
        }
        if handleAudioSessionActivation && !activateAudioSession() {
            // The system refuses to let this app play right now (a phone call is in progress, for example). Dart has
            // already set `playing`, so answer the request and tell it to revert.
            result([String: Any]())
            dataEvents.sendEvent(["playing": false])
            return
        }
        // Playing on purpose supersedes an interruption that was waiting to be resumed.
        resumeAfterInterruption = false
        if let playResult {
            playResult([String: Any]())
        }
        playResult = result
        playing = true
        player?.rate = speed
        updatePosition()
    }

    func pause() {
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

    func complete() {
        updatePosition()
        processingState = .completed
        broadcastPlaybackEvent()
        if let playResult {
            playResult([String: Any]())
            self.playResult = nil
        }
    }

    func seek(_ requestedPosition: CMTime?, index newIndex: Int?, completionHandler: @escaping (Bool) -> Void) throws {
        if processingState == .idle || processingState == .loading {
            completionHandler(false)
            return
        }
        let targetIndex = newIndex ?? index
        guard indexedAudioSources.indices.contains(targetIndex), let currentSource else {
            throw PlayerError.invalidIndex
        }
        // Without a position, start at the beginning, or at the live edge when the current item is a live stream.
        var position = CMTime.zero
        if let requestedPosition {
            position = requestedPosition
        } else if targetIndex == index, let item = currentSource.playerItem,
                  item.status == .readyToPlay, item.duration.isIndefinite {
            position = .positiveInfinity
        }
        // Only the latest seek updates the player state when it completes; every seek is answered exactly once.
        seekGeneration += 1
        let generation = seekGeneration
        var replied = false
        let complete: (Bool) -> Void = { finished in
            if replied { return }
            replied = true
            completionHandler(finished)
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
                    if self.disposed {
                        // Nothing may be sent once the engine is going away; an explicit disposal still answers the call.
                        if !self.disposedFromDeinit { complete(false) }
                        return
                    }
                    guard generation == self.seekGeneration else {
                        complete(finished)
                        return
                    }
                    if !self.playing {
                        // When playing, this is handled by timeControlStatus.
                        if self.bufferUnconfirmed, source.playerItem?.status == .readyToPlay,
                           self.player?.currentItem?.isPlaybackBufferEmpty != true {
                            // The item is ready and has data, which confirms the buffer.
                            self.bufferUnconfirmed = false
                        }
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
                    complete(finished)
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
                complete(true)
            }
        } else {
            // Seek within an item
            if playing {
                player?.pause()
            }
            seekPos = position
            enterBuffering("seek")
            updatePosition()
            broadcastPlaybackEvent()
            currentSource.seek(position) { finished in
                if self.disposed {
                    // Nothing may be sent once the engine is going away; an explicit disposal still answers the call.
                    if !self.disposedFromDeinit { complete(false) }
                    return
                }
                guard generation == self.seekGeneration else {
                    complete(finished)
                    return
                }
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
                complete(finished)
            }
        }
    }
}
