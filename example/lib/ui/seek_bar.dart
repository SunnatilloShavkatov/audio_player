import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:material_ui/material_ui.dart';

/// [SeekBar] wired to [player]'s position, buffered position and duration.
class PlayerSeekBar extends StatelessWidget {
  const new(this.player, {super.key});

  /// The player to show and control.
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => StreamBuilder<PositionData>(
    stream: player.positionDataStream,
    builder: (context, snapshot) {
      final positionData = snapshot.data;
      return SeekBar(
        duration: positionData?.duration ?? Duration.zero,
        position: positionData?.position ?? Duration.zero,
        bufferedPosition: positionData?.bufferedPosition ?? Duration.zero,
        onChangeEnd: (position) => unawaited(player.seek(position).catchError((Object _) {})),
      );
    },
  );
}

/// Seek slider with the buffered range drawn behind the thumb and the position and duration underneath.
class SeekBar extends StatefulWidget {
  const new({
    super.key,
    required this.duration,
    required this.position,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
  });

  /// Length of the current item. [Duration.zero] disables the slider.
  final Duration duration;

  /// Current playback position.
  final Duration position;

  /// How far the item has been buffered.
  final Duration bufferedPosition;

  /// Called while the user drags the thumb.
  final ValueChanged<Duration>? onChanged;

  /// Called when the user releases the thumb.
  final ValueChanged<Duration>? onChangeEnd;

  @override
  SeekBarState createState() => SeekBarState();
}

/// State of [SeekBar]; keeps the drag position until the user releases the thumb.
class SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = widget.duration.inMilliseconds.toDouble();
    final enabled = max > 0;
    final value = enabled ? (_dragValue ?? widget.position.inMilliseconds.toDouble()).clamp(0.0, max) : 0.0;
    final buffered = enabled ? widget.bufferedPosition.inMilliseconds.toDouble().clamp(0.0, max) : 0.0;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          max: enabled ? max : 1,
          value: value,
          secondaryTrackValue: buffered,
          onChanged: enabled
              ? (value) {
                  setState(() => _dragValue = value);
                  widget.onChanged?.call(Duration(milliseconds: value.round()));
                }
              : null,
          onChangeEnd: (value) {
            widget.onChangeEnd?.call(Duration(milliseconds: value.round()));
            _dragValue = null;
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(formatDuration(Duration(milliseconds: value.round())), style: labelStyle),
              const Spacer(),
              Text(enabled ? formatDuration(widget.duration) : '--:--', style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}
