import 'package:audio_player/audio_player.dart';
import 'package:rxdart/rxdart.dart';

export 'ui/artwork.dart';
export 'ui/now_playing.dart';
export 'ui/playback_settings.dart';
export 'ui/seek_bar.dart';
export 'ui/theme.dart';
export 'ui/transport_controls.dart';

/// Position, buffered position and duration of the current item, combined for a seek bar.
class PositionData {
  new(this.position, this.bufferedPosition, this.duration);

  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
}

/// Streams shared by the demo screens.
extension DemoPlayerStreams on AudioPlayer {
  /// Collects the data needed by a seek bar, combining the 3 streams of interest into one.
  Stream<PositionData> get positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
    positionStream,
    bufferedPositionStream,
    durationStream,
    (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero),
  );
}

/// Formats [duration] as `m:ss`, or `h:mm:ss` when it is an hour or longer.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
}

T? ambiguate<T>(T? value) => value;
