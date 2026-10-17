import AVFoundation

final class ClippingAudioSource: IndexedAudioSource {
    let audioSource: UriAudioSource
    private let start: CMTime
    private let end: CMTime

    /// `start` and `end` are in microseconds.
    init(id: String, audioSource: UriAudioSource, start: Int64?, end: Int64?) {
        self.audioSource = audioSource
        self.start = start.map { CMTime(value: $0, timescale: 1_000_000) } ?? .zero
        self.end = end.map { CMTime(value: $0, timescale: 1_000_000) } ?? .invalid
        super.init(id: id)
    }

    override var lazyLoading: Bool {
        get { audioSource.lazyLoading }
        set { audioSource.lazyLoading = newValue }
    }

    override func findById(_ sourceId: String, matches: inout [AudioSource]) {
        super.findById(sourceId, matches: &matches)
        audioSource.findById(sourceId, matches: &matches)
    }

    override func attach(_ player: AVQueuePlayer, initialPos: CMTime) {
        // Force super.attach to correct for the initial position.
        let initialPos = initialPos.isValid ? initialPos : .zero
        // Prepare clip to start/end at the right timestamps.
        audioSource.playerItem?.forwardPlaybackEndTime = end
        super.attach(player, initialPos: initialPos)
    }

    override var playerItem: IndexedPlayerItem? { audioSource.playerItem }
    override var playerItem2: IndexedPlayerItem? { audioSource.playerItem2 }

    override func getShuffleIndices() -> [Int] {
        [0]
    }

    override func seek(_ position: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        if completionHandler == nil || playerItem?.status == .readyToPlay {
            let absPosition = CMTimeAdd(start, position)
            audioSource.playerItem?.seek(to: absPosition, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completionHandler)
        } else {
            super.seek(position, completionHandler: completionHandler)
        }
    }

    override func flip() {
        audioSource.flip()
    }

    override func preparePlayerItem2() {
        if playerItem2 != nil { return }
        audioSource.preparePlayerItem2()
        guard let item = audioSource.playerItem2 else { return }
        // Prepare loop clip to start/end at the right timestamps.
        item.forwardPlaybackEndTime = end
        item.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
    }

    override var duration: CMTime {
        guard let playerItem else { return .invalid }
        return CMTimeSubtract(end.isValid ? end : playerItem.duration, start)
    }

    override var position: CMTime {
        guard let playerItem else { return .invalid }
        return CMTimeSubtract(playerItem.currentTime(), start)
    }

    override var bufferedPosition: CMTime {
        let pos = CMTimeSubtract(audioSource.bufferedPosition, start)
        let dur = duration
        return CMTimeCompare(pos, dur) >= 0 ? dur : pos
    }

    override func applyCanUseNetworkResourcesForLiveStreamingWhilePaused() {
        audioSource.applyCanUseNetworkResourcesForLiveStreamingWhilePaused()
    }

    override func applyPreferredPeakBitRate() {
        audioSource.applyPreferredPeakBitRate()
    }
}
