import AVFoundation

final class UriAudioSource: IndexedAudioSource {
    let uri: String
    private var item: IndexedPlayerItem?
    private var item2: IndexedPlayerItem?
    private let loadControl: LoadControl
    private let headers: [String: String]?
    private let options: [String: Any]?

    init(id: String, uri: String, loadControl: LoadControl, headers: [String: String]?, options: [String: Any]?) {
        self.uri = uri
        self.loadControl = loadControl
        self.headers = headers
        self.options = options
        super.init(id: id)
        item = createPlayerItem(uri)
    }

    override var playerItem: IndexedPlayerItem? { item }
    override var playerItem2: IndexedPlayerItem? { item2 }

    private func createPlayerItem(_ uri: String) -> IndexedPlayerItem {
        var assetOptions: [String: Any] = [:]

        if let darwinOptions = options?["darwinAssetOptions"] as? [String: Any] {
            assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = darwinOptions["preferPreciseDurationAndTiming"]
        }

        let asset: AVURLAsset
        if uri.hasPrefix("file://") {
            let path = String((uri.removingPercentEncoding ?? uri).dropFirst("file://".count))
            asset = AVURLAsset(url: URL(fileURLWithPath: path), options: assetOptions)
        } else {
            if var headers {
                // Use user-agent key if it is the only header and the API is supported.
                if headers.count == 1, #available(macOS 13.0, iOS 16.0, *) {
                    if let userAgent = headers.removeValue(forKey: "User-Agent") ?? headers.removeValue(forKey: "user-agent") {
                        assetOptions[AVURLAssetHTTPUserAgentKey] = userAgent
                    }
                }
                if !headers.isEmpty {
                    assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
                }
            }
            let url = URL(string: uri) ?? URL(fileURLWithPath: uri)
            asset = AVURLAsset(url: url, options: assetOptions)
        }

        let item = IndexedPlayerItem(asset: asset)
        // This does the best at reducing distortion on voice with speeds below 1.0
        item.audioTimePitchAlgorithm = .timeDomain
        if let duration = loadControl.preferredForwardBufferDuration {
            item.preferredForwardBufferDuration = Self.seconds(fromMicroseconds: duration)
        }
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused
        if let bitRate = loadControl.preferredPeakBitRate {
            item.preferredPeakBitRate = bitRate
        }
        return item
    }

    private static func seconds(fromMicroseconds microseconds: Int64) -> Double {
        Double(microseconds / 1000) / 1000.0
    }

    private var seekableRange: CMTimeRange? {
        item?.seekableTimeRanges.last?.timeRangeValue
    }

    // Not used. XXX: Remove?
    override func applyPreferredForwardBufferDuration() {
        guard let duration = loadControl.preferredForwardBufferDuration else { return }
        let value = Self.seconds(fromMicroseconds: duration)
        item?.preferredForwardBufferDuration = value
        item2?.preferredForwardBufferDuration = value
    }

    override func applyCanUseNetworkResourcesForLiveStreamingWhilePaused() {
        item?.canUseNetworkResourcesForLiveStreamingWhilePaused = loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused
        item2?.canUseNetworkResourcesForLiveStreamingWhilePaused = loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused
    }

    override func applyPreferredPeakBitRate() {
        guard let bitRate = loadControl.preferredPeakBitRate else { return }
        item?.preferredPeakBitRate = bitRate
        item2?.preferredPeakBitRate = bitRate
    }

    override func getShuffleIndices() -> [Int] {
        [0]
    }

    override func seek(_ position: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        if completionHandler == nil || item?.status == .readyToPlay {
            var position = position
            if let range = seekableRange {
                position = CMTimeAdd(position, range.start)
            }
            item?.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completionHandler)
        } else {
            super.seek(position, completionHandler: completionHandler)
        }
    }

    override func flip() {
        swap(&item, &item2)
    }

    override func preparePlayerItem2() {
        if item2 == nil {
            item2 = createPlayerItem(uri)
            item2?.audioSource = item?.audioSource
        }
    }

    override var duration: CMTime {
        if let range = seekableRange {
            return range.duration
        }
        return item?.duration ?? .invalid
    }

    override var position: CMTime {
        guard let item else { return .invalid }
        if let range = seekableRange {
            return CMTimeSubtract(item.currentTime(), range.start)
        }
        return item.currentTime()
    }

    override var bufferedPosition: CMTime {
        guard let item else { return .invalid }
        if let range = item.loadedTimeRanges.last?.timeRangeValue {
            return CMTimeAdd(range.start, range.duration)
        }
        return item.currentTime()
    }
}
