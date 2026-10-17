import 'package:audio_player/src/audio_player.dart';
import 'package:meta/meta.dart';

/// Encapsulates the playback event and the playing state of the player.
@immutable
class PlayerEvent {
  new({PlaybackEvent? playbackEvent, this.playing = false}) : playbackEvent = playbackEvent ?? PlaybackEvent();

  /// The current [PlaybackEvent]
  final PlaybackEvent playbackEvent;

  /// Whether the player is currently playing.
  final bool playing;

  PlayerEvent copyWith({PlaybackEvent? playbackEvent, bool? playing}) =>
      PlayerEvent(playbackEvent: playbackEvent ?? this.playbackEvent, playing: playing ?? this.playing);

  @override
  int get hashCode => Object.hash(playbackEvent.hashCode, playing);

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is PlayerEvent &&
      playbackEvent == other.playbackEvent &&
      playing == other.playing;

  @override
  String toString() => '{playbackEvent=$playbackEvent, playing=$playing}';
}

/// Encapsulates the playback state and current position of the player.
@immutable
class PlaybackEvent {
  new({
    this.processingState = ProcessingState.idle,
    DateTime? updateTime,
    this.updatePosition = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration,
    this.icyMetadata,
    this.currentIndex,
    this.androidAudioSessionId,
    this.errorCode,
    this.errorMessage,
  }) : updateTime = updateTime ?? DateTime.now();

  /// The current processing state.
  final ProcessingState processingState;

  /// When the last time a position discontinuity happened, as measured in time
  /// since the epoch.
  final DateTime updateTime;

  /// The position at [updateTime].
  final Duration updatePosition;

  /// The buffer position.
  final Duration bufferedPosition;

  /// The media duration, or `null` if unknown.
  final Duration? duration;

  /// The latest ICY metadata received through the audio stream if available.
  final IcyMetadata? icyMetadata;

  /// The index of the currently playing item, or `null` if no item is selected.
  // TODO(SunnatilloShavkatov): Consider introducing currentAudioSourceId
  final int? currentIndex;

  /// The current Android AudioSession ID if set.
  final int? androidAudioSessionId;

  /// The error code of the most recent playback error, or `null` if none.
  ///
  /// Supported on Android, iOS and macOS.
  final int? errorCode;

  /// The error message of the most recent playback error, or `null` if none.
  ///
  /// Supported on Android, iOS and macOS.
  final String? errorMessage;

  /// Returns a copy of this event with given properties replaced.
  PlaybackEvent copyWith({
    ProcessingState? processingState,
    DateTime? updateTime,
    Duration? updatePosition,
    Duration? bufferedPosition,
    Duration? duration,
    IcyMetadata? icyMetadata,
    int? currentIndex,
    int? androidAudioSessionId,
    int? errorCode,
    String? errorMessage,
  }) => PlaybackEvent(
    processingState: processingState ?? this.processingState,
    updateTime: updateTime ?? this.updateTime,
    updatePosition: updatePosition ?? this.updatePosition,
    bufferedPosition: bufferedPosition ?? this.bufferedPosition,
    duration: duration ?? this.duration,
    icyMetadata: icyMetadata ?? this.icyMetadata,
    currentIndex: currentIndex ?? this.currentIndex,
    androidAudioSessionId: androidAudioSessionId ?? this.androidAudioSessionId,
    errorCode: errorCode ?? this.errorCode,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  @override
  int get hashCode => Object.hash(
    processingState,
    updateTime,
    updatePosition,
    bufferedPosition,
    duration,
    icyMetadata,
    currentIndex,
    androidAudioSessionId,
    errorCode,
    errorMessage,
  );

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is PlaybackEvent &&
      processingState == other.processingState &&
      updateTime == other.updateTime &&
      updatePosition == other.updatePosition &&
      bufferedPosition == other.bufferedPosition &&
      duration == other.duration &&
      icyMetadata == other.icyMetadata &&
      currentIndex == other.currentIndex &&
      androidAudioSessionId == other.androidAudioSessionId &&
      errorCode == other.errorCode &&
      errorMessage == other.errorMessage;

  @override
  String toString() =>
      '{processingState=$processingState, updateTime=$updateTime, updatePosition=$updatePosition, bufferedPosition=$bufferedPosition, duration=$duration, currentIndex=$currentIndex}';
}

/// Enumerates the different processing states of a player.
enum ProcessingState {
  /// The player has not loaded an [AudioSource].
  idle,

  /// The player is loading an [AudioSource].
  loading,

  /// The player is buffering audio and unable to play.
  buffering,

  /// The player is has enough audio buffered and is able to play.
  ready,

  /// The player has reached the end of the audio.
  completed,
}

/// Encapsulates the playing and processing states. These two states vary
/// orthogonally, and so if [processingState] is [ProcessingState.buffering],
/// you can check [playing] to determine whether the buffering occurred while
/// the player was playing or while the player was paused.
@immutable
class PlayerState {
  const new({required this.playing, required this.processingState});

  /// Whether the player will play when [processingState] is
  /// [ProcessingState.ready].
  final bool playing;

  /// The current processing state of the player.
  final ProcessingState processingState;

  @override
  String toString() => 'playing=$playing,processingState=$processingState';

  @override
  int get hashCode => Object.hash(playing, processingState);

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is PlayerState &&
      other.playing == playing &&
      other.processingState == processingState;
}

/// An enumeration of modes that can be passed to [AudioPlayer.setLoopMode].
enum LoopMode { off, one, all }
