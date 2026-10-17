import AVFoundation

class AudioSource {
    let sourceId: String

    init(id: String) {
        sourceId = id
    }

    var lazyLoading: Bool {
        get { false }
        set {}
    }

    @discardableResult
    func buildSequence(_ sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        0
    }

    func findById(_ sourceId: String, matches: inout [AudioSource]) {
        if self.sourceId == sourceId {
            matches.append(self)
        }
    }

    func getShuffleIndices() -> [Int] {
        []
    }

    func decodeShuffleOrder(_ dict: [String: Any]) {}
}
