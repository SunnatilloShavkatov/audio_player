part of '../audio_player.dart';

/// The root playlist of an [AudioPlayer]: a concatenation of audio sources to
/// be played in succession. Playback between items is gapless on Android, iOS
/// and macOS.
///
/// Audio sources can be dynamically added, removed and reordered while the
/// audio is playing via the playlist methods on [AudioPlayer].
class _PlaylistAudioSource extends AudioSource {
  /// Creates a playlist with the specified [children]. If [useLazyPreparation]
  /// is `true`, children will be loaded/buffered as late as possible before
  /// needed for playback (currently supported on Android, iOS, MacOS). When
  /// [AudioPlayer.shuffleModeEnabled] is `true`, [shuffleOrder] will be used to
  /// determine the playback order (defaulting to [DefaultShuffleOrder]).
  new({required this.children, this.useLazyPreparation = true, ShuffleOrder? shuffleOrder})
    : _shuffleOrder = shuffleOrder ?? DefaultShuffleOrder()
        ..insert(0, children.length),
      super(id: '');
  final _lock = Lock();
  final List<AudioSource> children;
  final bool useLazyPreparation;
  ShuffleOrder _shuffleOrder;

  @override
  void _onAttach(AudioPlayer player) {
    super._onAttach(player);
    for (final source in children) {
      source._onAttach(player);
    }
  }

  @override
  Future<void> _onLoad() async {
    await super._onLoad();
    for (final source in children) {
      await source._onLoad();
    }
  }

  @override
  void _shuffle({int? initialIndex}) {
    int? localInitialIndex;
    // si = index in [sequence]
    // ci = index in [children] array.
    for (var ci = 0, si = 0; ci < children.length; ci++) {
      final child = children[ci];
      final childLength = child.sequence.length;
      final initialIndexWithinThisChild = initialIndex != null && initialIndex >= si && initialIndex < si + childLength;
      if (initialIndexWithinThisChild) {
        localInitialIndex = ci;
      }
      final childInitialIndex = initialIndexWithinThisChild ? (initialIndex - si) : null;
      child._shuffle(initialIndex: childInitialIndex);
      si += childLength;
    }
    _shuffleOrder.shuffle(initialIndex: localInitialIndex);
  }

  /// Appends an [AudioSource].
  Future<void> add(AudioSource audioSource) => _lock.synchronized(() async {
    final index = children.length;
    children.add(audioSource);
    _shuffleOrder.insert(index, 1);
    final player = _player;
    if (player != null) {
      audioSource._onAttach(player);
      await player._broadcastSequence();
      if (player._active) {
        await audioSource._onLoad();
      }
      await (await player._platform).concatenatingInsertAll(
        ConcatenatingInsertAllRequest(
          id: _id,
          index: index,
          children: [audioSource._toMessage()],
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
    }
  });

  /// Inserts an [AudioSource] at [index].
  Future<void> insert(int index, AudioSource audioSource) => _lock.synchronized(() async {
    children.insert(index, audioSource);
    _shuffleOrder.insert(index, 1);
    final player = _player;
    if (player != null) {
      audioSource._onAttach(player);
      await player._broadcastSequence();
      if (player._active) {
        await audioSource._onLoad();
      }
      await (await player._platform).concatenatingInsertAll(
        ConcatenatingInsertAllRequest(
          id: _id,
          index: index,
          children: [audioSource._toMessage()],
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
    }
  });

  /// Appends multiple [AudioSource]s.
  Future<void> addAll(List<AudioSource> children) => _lock.synchronized(() async {
    final index = this.children.length;
    this.children.addAll(children);
    _shuffleOrder.insert(index, children.length);
    final player = _player;
    if (player != null) {
      for (final child in children) {
        child._onAttach(player);
      }
      await player._broadcastSequence();
      if (player._active) {
        for (final child in children) {
          await child._onLoad();
        }
      }
      await (await player._platform).concatenatingInsertAll(
        ConcatenatingInsertAllRequest(
          id: _id,
          index: index,
          children: children.map((child) => child._toMessage()).toList(),
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
    }
  });

  /// Inserts multiple [AudioSource]s at [index].
  Future<void> insertAll(int index, List<AudioSource> children) => _lock.synchronized(() async {
    this.children.insertAll(index, children);
    _shuffleOrder.insert(index, children.length);
    final player = _player;
    if (player != null) {
      for (final child in children) {
        child._onAttach(player);
      }
      await player._broadcastSequence();
      if (player._active) {
        for (final child in children) {
          await child._onLoad();
        }
      }
      await (await player._platform).concatenatingInsertAll(
        ConcatenatingInsertAllRequest(
          id: _id,
          index: index,
          children: children.map((child) => child._toMessage()).toList(),
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
    }
  });

  /// Dynamically removes an [AudioSource] at [index] after this playlist has
  /// already been loaded.
  Future<void> removeAt(int index) => _lock.synchronized(() async {
    children.removeAt(index);
    _shuffleOrder.removeRange(index, index + 1);
    final player = _player;
    if (player != null) {
      await player._broadcastSequence();
      await (await player._platform).concatenatingRemoveRange(
        ConcatenatingRemoveRangeRequest(
          id: _id,
          startIndex: index,
          endIndex: index + 1,
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
      player._unregisterDetachedAudioSources();
    }
  });

  /// Removes a range of [AudioSource]s from index [start] inclusive to [end]
  /// exclusive.
  Future<void> removeRange(int start, int end) => _lock.synchronized(() async {
    children.removeRange(start, end);
    _shuffleOrder.removeRange(start, end);
    final player = _player;
    if (player != null) {
      await player._broadcastSequence();
      await (await player._platform).concatenatingRemoveRange(
        ConcatenatingRemoveRangeRequest(
          id: _id,
          startIndex: start,
          endIndex: end,
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
      player._unregisterDetachedAudioSources();
    }
  });

  /// Moves an [AudioSource] from [currentIndex] to [newIndex].
  Future<void> move(int currentIndex, int newIndex) => _lock.synchronized(() async {
    children.insert(newIndex, children.removeAt(currentIndex));
    _shuffleOrder
      ..removeRange(currentIndex, currentIndex + 1)
      ..insert(newIndex, 1);
    final player = _player;
    if (player != null) {
      await player._broadcastSequence();
      await (await player._platform).concatenatingMove(
        ConcatenatingMoveRequest(
          id: _id,
          currentIndex: currentIndex,
          newIndex: newIndex,
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
    }
  });

  /// Removes all [AudioSource]s.
  Future<void> clear() => _lock.synchronized(() async {
    final end = children.length;
    children.clear();
    _shuffleOrder.clear();
    final player = _player;
    if (player != null) {
      await player._broadcastSequence();
      await (await player._platform).concatenatingRemoveRange(
        ConcatenatingRemoveRangeRequest(
          id: _id,
          startIndex: 0,
          endIndex: end,
          shuffleOrder: List.of(_shuffleOrder.indices),
        ),
      );
      player._unregisterDetachedAudioSources();
    }
  });

  /// Initialise without communicating with platform.
  Future<void> _init(List<AudioSource> children, ShuffleOrder shuffleOrder) => _lock.synchronized(() async {
    this.children.replaceRange(0, this.children.length, children);
    _shuffleOrder = shuffleOrder
      ..clear()
      ..insert(0, children.length);
    final player = _player;
    if (player != null) {
      for (final child in children) {
        child._onAttach(player);
      }
      await player._broadcastSequence();
      if (player._active) {
        for (final child in children) {
          await child._onLoad();
        }
      }
    }
  });

  /// The number of [AudioSource]s.
  int get length => children.length;

  AudioSource operator [](int index) => children[index];

  @override
  List<IndexedAudioSource> get sequence => children.expand((s) => s.sequence).toList();

  @override
  List<int> get shuffleIndices {
    var offset = 0;
    final childIndicesList = <List<int>>[];
    for (final child in children) {
      final childIndices = child.shuffleIndices.map((i) => i + offset).toList();
      childIndicesList.add(childIndices);
      offset += childIndices.length;
    }
    final indices = <int>[];
    for (final index in _shuffleOrder.indices) {
      indices.addAll(childIndicesList[index]);
    }
    return indices;
  }

  @override
  AudioSourceMessage _toMessage() => ConcatenatingAudioSourceMessage(
    id: _id,
    children: children.map((child) => child._toMessage()).toList(),
    useLazyPreparation: useLazyPreparation,
    shuffleOrder: _shuffleOrder.indices,
  );
}

/// An [AudioSource] that clips the audio of a [UriAudioSource] between a
/// certain start and end time.
class ClippingAudioSource extends IndexedAudioSource {
  /// Creates an audio source that clips [child] to the range [start]..[end],
  /// where [start] and [end] default to the beginning and end of the original
  /// [child] source.
  new({required this.child, this.start, this.end, super.tag, super.duration});

  final UriAudioSource child;
  final Duration? start;
  final Duration? end;

  @override
  void _onAttach(AudioPlayer player) {
    super._onAttach(player);
    child._onAttach(player);
  }

  @override
  Future<void> _onLoad() async {
    await super._onLoad();
    await child._onLoad();
  }

  @override
  AudioSourceMessage _toMessage() => ClippingAudioSourceMessage(
    id: _id,
    child: child._toMessage() as UriAudioSourceMessage,
    start: start,
    end: end,
    tag: tag,
  );
}
