import AVFoundation

final class ConcatenatingAudioSource: AudioSource {
    private var audioSources: [AudioSource]
    private var shuffleOrder: [Int]

    init(id: String, audioSources: [AudioSource], shuffleOrder: [Int], lazyLoading: Bool) {
        self.audioSources = audioSources
        self.shuffleOrder = shuffleOrder
        super.init(id: id)
        self.lazyLoading = lazyLoading
    }

    var count: Int { audioSources.count }

    override var lazyLoading: Bool {
        get { audioSources.first?.lazyLoading ?? false }
        set {
            for source in audioSources {
                source.lazyLoading = newValue
            }
        }
    }

    func insertSource(_ audioSource: AudioSource, at index: Int) {
        audioSources.insert(audioSource, at: min(max(index, 0), audioSources.count))
    }

    /// Removes the sources in `start..<end`. An `end` of -1 means the end of the list.
    func removeSources(from start: Int, to end: Int) {
        let end = end == -1 ? audioSources.count : min(end, audioSources.count)
        guard start >= 0, start < end else { return }
        audioSources.removeSubrange(start..<end)
    }

    func moveSource(from currentIndex: Int, to newIndex: Int) {
        guard audioSources.indices.contains(currentIndex) else { return }
        let source = audioSources.remove(at: currentIndex)
        audioSources.insert(source, at: min(max(newIndex, 0), audioSources.count))
    }

    func setShuffleOrder(_ shuffleOrder: [Int]) {
        self.shuffleOrder = shuffleOrder
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
        var offset = 0
        var childOrders: [[Int]] = []
        for source in audioSources {
            let childShuffleIndices = source.getShuffleIndices()
            childOrders.append(childShuffleIndices.map { $0 + offset })
            offset += childShuffleIndices.count
        }
        var order: [Int] = []
        for i in 0..<audioSources.count where i < shuffleOrder.count {
            let childIndex = shuffleOrder[i]
            if childOrders.indices.contains(childIndex) {
                order.append(contentsOf: childOrders[childIndex])
            }
        }
        return order
    }

    override func decodeShuffleOrder(_ dict: [String: Any]) {
        shuffleOrder = (dict["shuffleOrder"] as? [Int]) ?? []
        let dictChildren = (dict["children"] as? [[String: Any]]) ?? []
        if audioSources.count != dictChildren.count {
            NSLog("decodeShuffleOrder Concatenating children don't match")
            return
        }
        for (child, dictChild) in zip(audioSources, dictChildren) {
            child.decodeShuffleOrder(dictChild)
        }
    }
}
