import 'dart:math';

import 'package:audio_player/src/audio_player.dart';

/// Defines the algorithm for shuffling the order of a playlist. See
/// [DefaultShuffleOrder] for a default implementation.
abstract class ShuffleOrder {
  const new();

  /// The shuffled list of indices of [AudioSource]s to play. For example,
  /// [2,0,1] specifies to play the 3rd, then the 1st, then the 2nd item.
  List<int> get indices;

  /// Shuffles the [indices]. If specified, [initialIndex] will be the first
  /// item in the shuffle order.
  void shuffle({int? initialIndex});

  /// Inserts [count] new consecutive indices starting from [index] into
  /// [indices], at random positions.
  void insert(int index, int count);

  /// Removes the indices that are `>= start` and `< end`.
  void removeRange(int start, int end);

  /// Removes all indices.
  void clear();
}

/// The default implementation of [ShuffleOrder] which shuffles items with the
/// currently playing item at the head of the order.
class DefaultShuffleOrder extends ShuffleOrder {
  new({Random? random}) : _random = random ?? Random();
  final Random _random;
  @override
  final indices = <int>[];

  @override
  void shuffle({int? initialIndex}) {
    assert(initialIndex == null || indices.contains(initialIndex), 'initialIndex must be one of the shuffled indices.');
    if (indices.length <= 1) {
      return;
    }
    indices.shuffle(_random);
    if (initialIndex == null) {
      return;
    }

    const initialPos = 0;
    final swapPos = indices.indexOf(initialIndex);
    // Swap the indices at initialPos and swapPos.
    final swapIndex = indices[initialPos];
    indices[initialPos] = initialIndex;
    indices[swapPos] = swapIndex;
  }

  @override
  void insert(int index, int count) {
    // Offset indices after insertion point.
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) {
        indices[i] += count;
      }
    }
    // Insert new indices at random positions after currentIndex.
    final newIndices = List.generate(count, (i) => index + i);
    for (final newIndex in newIndices) {
      final insertionIndex = _random.nextInt(indices.length + 1);
      indices.insert(insertionIndex, newIndex);
    }
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    // Remove old indices.
    final oldIndices = List.generate(count, (i) => start + i).toSet();
    indices.removeWhere(oldIndices.contains);
    // Offset indices after deletion point.
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= end) {
        indices[i] -= count;
      }
    }
  }

  @override
  void clear() {
    indices.clear();
  }
}
