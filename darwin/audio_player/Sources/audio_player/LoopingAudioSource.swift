import AVFoundation

final class LoopingAudioSource: AudioSource {
    // An array of duplicates
    private let audioSources: [AudioSource]

    init(id: String, audioSources: [AudioSource]) {
        self.audioSources = audioSources
        super.init(id: id)
    }

    override var lazyLoading: Bool {
        get { audioSources.first?.lazyLoading ?? false }
        set {
            for source in audioSources {
                source.lazyLoading = newValue
            }
        }
    }

    override func buildSequence(_ sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        var treeIndex = treeIndex
        for source in audioSources {
            treeIndex = source.buildSequence(&sequence, treeIndex: treeIndex)
        }
        return treeIndex
    }

    override func findById(_ sourceId: String, matches: inout [AudioSource]) {
        super.findById(sourceId, matches: &matches)
        for source in audioSources {
            source.findById(sourceId, matches: &matches)
        }
    }

    override func getShuffleIndices() -> [Int] {
        var order: [Int] = []
        var offset = 0
        for source in audioSources {
            let childShuffleOrder = source.getShuffleIndices()
            order.append(contentsOf: childShuffleOrder.map { $0 + offset })
            offset += childShuffleOrder.count
        }
        return order
    }

    override func decodeShuffleOrder(_ dict: [String: Any]) {
        guard let dictChild = dict["child"] as? [String: Any] else { return }
        for child in audioSources {
            child.decodeShuffleOrder(dictChild)
        }
    }
}
