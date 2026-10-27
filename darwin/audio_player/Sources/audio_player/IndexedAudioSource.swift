import AVFoundation

class IndexedAudioSource: AudioSource {
    private(set) var isAttached = false
    private var _lazyLoading = false
    private var queuedSeekPos = CMTime.invalid
    private var queuedSeekCompletionHandler: ((Bool) -> Void)?

    var playerItem: IndexedPlayerItem? { nil }
    var playerItem2: IndexedPlayerItem? { nil }
    var duration: CMTime { .invalid }
    var position: CMTime { .invalid }
    var bufferedPosition: CMTime { .invalid }

    override var lazyLoading: Bool {
        get { _lazyLoading }
        set { _lazyLoading = newValue }
    }

    func onStatusChanged(_ status: AVPlayerItem.Status) {
        if status == .readyToPlay, let handler = queuedSeekCompletionHandler {
            // This handles a pending seek during a load. Clear the queue first so that nothing queued while the seek
            // runs is lost.
            let position = queuedSeekPos
            queuedSeekPos = .invalid
            queuedSeekCompletionHandler = nil
            seek(position, completionHandler: handler)
        } else if status == .failed, playerItem?.status == .failed {
            // The item will never become ready, so the queued seek can't run.
            cancelQueuedSeek()
        }
    }

    /// Completes a seek that is still waiting for the item to become ready, reporting that it didn't finish.
    func cancelQueuedSeek() {
        let handler = queuedSeekCompletionHandler
        queuedSeekPos = .invalid
        queuedSeekCompletionHandler = nil
        handler?(false)
    }

    override func buildSequence(_ sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        sequence.append(self)
        return treeIndex + 1
    }

    func attach(_ player: AVQueuePlayer, initialPos: CMTime) {
        isAttached = true
        if initialPos.isValid {
            seek(initialPos)
        }
    }

    func seek(_ position: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        if completionHandler != nil && playerItem?.status != .readyToPlay {
            // Only one seek can wait for the item; the one it replaces is superseded.
            let superseded = queuedSeekCompletionHandler
            queuedSeekPos = position
            queuedSeekCompletionHandler = completionHandler
            superseded?(false)
        }
    }

    func flip() {}

    func preparePlayerItem2() {}

    func applyCanUseNetworkResourcesForLiveStreamingWhilePaused() {}

    func applyPreferredPeakBitRate() {}
}
