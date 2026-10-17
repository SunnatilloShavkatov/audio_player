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
            // This handles a pending seek during a load.
            // TODO: Test seeking during a seek.
            seek(queuedSeekPos, completionHandler: handler)
            queuedSeekPos = .invalid
            queuedSeekCompletionHandler = nil
        }
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
            queuedSeekPos = position
            queuedSeekCompletionHandler = completionHandler
        }
    }

    func flip() {}

    func preparePlayerItem2() {}

    func applyCanUseNetworkResourcesForLiveStreamingWhilePaused() {}

    func applyPreferredPeakBitRate() {}
}
