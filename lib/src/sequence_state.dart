import 'dart:math';

import 'package:audio_player/src/audio_player.dart';
import 'package:audio_player/src/player_state.dart';

/// Encapsulates the [sequence] and [currentIndex] state and ensures
/// consistency such that [currentIndex] is within the range of
/// `sequence.length`. If `sequence.length` is 0, then [currentIndex] is also
/// 0.
class SequenceState {
  new({
    required this.sequence,
    required this._currentIndex,
    required this.shuffleIndices,
    required this.shuffleModeEnabled,
    required this.loopMode,
  });
  static const _defaultInt = -9999999;

  /// The current sequence of [IndexedAudioSource]s.
  final List<IndexedAudioSource> sequence;

  /// The index of the current source in the sequence.
  int? get currentIndex => sequence.isNotEmpty ? min(_currentIndex ?? 0, sequence.length - 1) : null;

  // The index of the current source in the sequence.
  final int? _currentIndex;

  /// The current shuffle order
  final List<int> shuffleIndices;

  /// Whether shuffle mode is enabled.
  final bool shuffleModeEnabled;

  /// The current loop mode.
  final LoopMode loopMode;

  /// The current source in the sequence.
  IndexedAudioSource? get currentSource => sequence.isEmpty || currentIndex == null ? null : sequence[currentIndex!];

  /// The effective sequence. This is equivalent to [sequence]. If
  /// [shuffleModeEnabled] is true, this is modulated by [shuffleIndices].
  List<IndexedAudioSource> get effectiveSequence =>
      shuffleModeEnabled ? shuffleIndices.map((i) => sequence[i]).toList() : sequence;

  /// Returns a copy of this [SequenceState] with the given properties replaced.
  SequenceState copyWith({
    List<IndexedAudioSource>? sequence,
    int? currentIndex = _defaultInt,
    List<int>? shuffleIndices,
    bool? shuffleModeEnabled,
    LoopMode? loopMode,
  }) => SequenceState(
    sequence: sequence ?? this.sequence,
    currentIndex: currentIndex != _defaultInt ? currentIndex : this.currentIndex,
    shuffleIndices: shuffleIndices ?? this.shuffleIndices,
    shuffleModeEnabled: shuffleModeEnabled ?? this.shuffleModeEnabled,
    loopMode: loopMode ?? this.loopMode,
  );
}

/// Information collected when a position discontinuity occurs.
class PositionDiscontinuity {
  const new(this.reason, this.previousEvent, this.event);

  /// The reason for the position discontinuity.
  final PositionDiscontinuityReason reason;

  /// The previous event before the position discontinuity.
  final PlaybackEvent previousEvent;

  /// The event that caused the position discontinuity.
  final PlaybackEvent event;
}

/// The reasons for position discontinuities.
enum PositionDiscontinuityReason {
  /// The position discontinuity was initiated by a seek.
  seek,

  /// The position discontinuity occurred because the player reached the end of
  /// the current item and auto-advanced to the next item.
  autoAdvance,
}
