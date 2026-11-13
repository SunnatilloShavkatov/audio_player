import AVFoundation

private let treadmillSize = 2

// The AVQueuePlayer queue: playlist edits, the play order, looping and the action at the end of an item.
extension AudioPlayer {
    // MARK: - Concatenation

    // Untested
    func concatenatingInsertAll(catId: String, index: Int, sources: [[String: Any]], shuffleOrder: [Int]) throws {
        guard let audioSource, let player else { return }
        // Find all duplicates of the identified ConcatenatingAudioSource.
        var matches: [AudioSource] = []
        audioSource.findById(catId, matches: &matches)
        // Decode for every match before changing any of them, so that an invalid source leaves them all intact.
        let catSources = matches.compactMap { $0 as? ConcatenatingAudioSource }
        let decodedSources = try catSources.map { _ in try decodeAudioSources(sources) }
        // Add each new source to each match.
        for (catSource, newSources) in zip(catSources, decodedSources) {
            let idx = index >= 0 ? index : catSource.count
            for (j, newSource) in newSources.enumerated() {
                catSource.insertSource(newSource, at: idx + j)
            }
            catSource.setShuffleOrder(shuffleOrder)
        }
        // Index the new audio sources.
        indexedAudioSources = []
        audioSource.buildSequence(&indexedAudioSources, treeIndex: 0)
        for source in indexedAudioSources where !source.isAttached {
            source.playerItem?.audioSource = source
            addItemObservers(source.playerItem)
        }
        updateOrder()
        let currentIndex = indexForItem(player.currentItem as? IndexedPlayerItem)
        self.index = currentIndex >= 0 ? currentIndex : clampedIndex()
        enqueueFrom(self.index)
        // Notify each new IndexedAudioSource that it's been attached to the player.
        for source in indexedAudioSources where !source.isAttached {
            source.attach(player, initialPos: .invalid)
        }
        broadcastPlaybackEvent()
    }

    // Untested
    func concatenatingRemoveRange(catId: String, start: Int, end: Int, shuffleOrder: [Int]) {
        guard let audioSource else { return }
        // Find all duplicates of the identified ConcatenatingAudioSource.
        var matches: [AudioSource] = []
        audioSource.findById(catId, matches: &matches)
        // Remove range from each match.
        for case let catSource as ConcatenatingAudioSource in matches {
            let endIndex = end >= 0 ? end : catSource.count
            catSource.removeSources(from: start, to: endIndex)
            catSource.setShuffleOrder(shuffleOrder)
        }
        // Re-index the remaining audio sources.
        let oldIndexedAudioSources = indexedAudioSources
        indexedAudioSources = []
        audioSource.buildSequence(&indexedAudioSources, treeIndex: 0)
        var j = 0
        func dropOldSource(at j: Int) {
            removeItemObservers(oldIndexedAudioSources[j].playerItem)
            removeItemObservers(oldIndexedAudioSources[j].playerItem2)
            if j < index {
                index -= 1
            }
            // Otherwise, if j == index, the currently playing item was removed.
        }
        for source in indexedAudioSources {
            while j < oldIndexedAudioSources.count && source !== oldIndexedAudioSources[j] {
                dropOldSource(at: j)
                j += 1
            }
            j += 1
        }
        // Sources removed from the end of the list.
        while j < oldIndexedAudioSources.count {
            dropOldSource(at: j)
            j += 1
        }
        updateOrder()
        if index >= indexedAudioSources.count { index = indexedAudioSources.count - 1 }
        if index < 0 { index = 0 }
        enqueueFrom(index)
        broadcastPlaybackEvent()
    }

    // Untested
    func concatenatingMove(catId: String, currentIndex: Int, newIndex: Int, shuffleOrder: [Int]) {
        guard let audioSource else { return }
        // Find all duplicates of the identified ConcatenatingAudioSource.
        var matches: [AudioSource] = []
        audioSource.findById(catId, matches: &matches)
        // Move range within each match.
        for case let catSource as ConcatenatingAudioSource in matches {
            catSource.moveSource(from: currentIndex, to: newIndex)
            catSource.setShuffleOrder(shuffleOrder)
        }
        // Re-index the audio sources.
        indexedAudioSources = []
        audioSource.buildSequence(&indexedAudioSources, treeIndex: 0)
        updateOrder()
        // Without a current item the lookup fails; keep the old index instead of reporting -1.
        let currentIndex = indexForItem(player?.currentItem as? IndexedPlayerItem)
        enqueueFrom(currentIndex >= 0 ? currentIndex : clampedIndex())
        broadcastPlaybackEvent()
    }

    /// The current index limited to the existing sources (0 when there are none).
    private func clampedIndex() -> Int {
        min(max(index, 0), max(indexedAudioSources.count - 1, 0))
    }

    // MARK: - Queue management

    func enqueueFrom(_ newIndex: Int) {
        index = newIndex

        guard let player else { return }

        // Update the queue while keeping the currently playing item untouched.

        // First, remove all player items except for the currently playing one (if any).
        let oldItem = player.currentItem as? IndexedPlayerItem
        var existingItem: IndexedPlayerItem?
        let newItem = currentSource?.playerItem
        // In the first pass, preserve the old and new items.
        for item in player.items() {
            if item === newItem {
                // Preserve and tag new item if it is already in the queue.
                existingItem = item as? IndexedPlayerItem
            } else if item === oldItem {
                // Temporarily preserve old item, just to avoid jumping to
                // intermediate queue positions unnecessarily. We only want to jump
                // once to the new index.
            } else {
                player.remove(item)
            }
        }
        // In the second pass, remove the old item (if different from new item).
        if let oldItem, newItem !== oldItem {
            player.remove(oldItem)
        }

        // Regenerate queue
        enqueuedAll = false
        if existingItem == nil || loopMode != .one {
            enqueuedAll = true
            var include = false
            for si in order where indexedAudioSources.indices.contains(si) {
                if si == index { include = true }
                let source = indexedAudioSources[si]
                if include, let item = source.playerItem, item !== existingItem {
                    if source.lazyLoading && player.items().count >= treadmillSize {
                        // Enqueue up until the first lazy item that does not fit on the treadmill.
                        enqueuedAll = false
                        break
                    }
                    player.insert(item, after: nil)
                    if loopMode == .one {
                        // We only want one item in the queue.
                        break
                    }
                }
            }
        }

        // Add next loop item if we're looping
        if let first = order.first {
            if loopMode == .all && enqueuedAll, indexedAudioSources.indices.contains(first) {
                insertLoopItem(of: indexedAudioSources[first], into: player)
            } else if loopMode == .one, let source = currentSource {
                insertLoopItem(of: source, into: player)
            }
        }

        if processingState != .loading && oldItem !== newItem {
            // Moving to another item ends the completed state; leaveBuffering would leave it untouched.
            if processingState == .completed {
                processingState = .ready
            }
            if player.currentItem?.isPlaybackBufferEmpty == true {
                enterBuffering("enqueueFrom playbackBufferEmpty")
            } else {
                leaveBuffering("enqueueFrom !playbackBufferEmpty")
            }
            updatePosition()
        }

        updateEndAction()
    }

    private func insertLoopItem(of source: IndexedAudioSource, into player: AVQueuePlayer) {
        if source.playerItem2 == nil {
            source.preparePlayerItem2()
        }
        // A loop item reused from a previous load has had its observers removed.
        addItemObservers(source.playerItem2)
        if let item = source.playerItem2 {
            player.insert(item, after: nil)
        }
    }

    func updateOrder() {
        orderInv = Array(repeating: 0, count: indexedAudioSources.count)
        if shuffleModeEnabled {
            order = audioSource?.getShuffleIndices() ?? []
        } else {
            order = Array(indexedAudioSources.indices)
        }
        for (i, si) in order.enumerated() where orderInv.indices.contains(si) {
            orderInv[si] = i
        }
    }

    /// The position of the source at `index` within the (possibly shuffled) play order.
    func orderPosition(of index: Int) -> Int {
        orderInv.indices.contains(index) ? orderInv[index] : 0
    }

    func updateEndAction() {
        // Should be called in the following situations:
        // - when the audio source changes
        // - when index changes
        // - when the loop mode changes.
        // - when the shuffle mode changes.
        guard let player else { return }
        if audioSource != nil && (loopMode != .off || (!order.isEmpty && orderPosition(of: index) + 1 < order.count)) {
            player.actionAtItemEnd = .advance
        } else {
            player.actionAtItemEnd = .pause // .none
        }
    }

    func indexForItem(_ playerItem: IndexedPlayerItem?) -> Int {
        guard let playerItem else { return -1 }
        return indexedAudioSources.firstIndex { $0.playerItem === playerItem || $0.playerItem2 === playerItem } ?? -1
    }
}
