import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rxdart/rxdart.dart';

/// A row of transport buttons around a large [PlayPauseButton].
class TransportControls extends StatelessWidget {
  const new(this.player, {super.key, this.leading = const [], this.trailing = const [], this.onReplay});

  /// The player to control.
  final AudioPlayer player;

  /// Buttons left of the play/pause button.
  final List<Widget> leading;

  /// Buttons right of the play/pause button.
  final List<Widget> trailing;

  /// What the play button does once playback has completed. Defaults to seeking to the start.
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ...leading,
        PlayPauseButton(player, onReplay: onReplay),
        ...trailing,
      ],
    ),
  );
}

/// Large circular play/pause button. Shows a progress ring while loading or buffering and a replay icon once
/// playback has completed. Disabled while the player has nothing to play.
class PlayPauseButton extends StatelessWidget {
  const new(this.player, {super.key, this.onReplay, this.size = 72});

  /// The player to control.
  final AudioPlayer player;

  /// What the button does once playback has completed. Defaults to seeking to the start.
  final VoidCallback? onReplay;

  /// Diameter of the button.
  final double size;

  @override
  Widget build(BuildContext context) => StreamBuilder<(bool, ProcessingState, int)>(
    stream: Rx.combineLatest2(
      player.playerEventStream,
      player.sequenceStream,
      (event, sequence) => (event.playing, event.playbackEvent.processingState, sequence.length),
    ),
    builder: (context, snapshot) {
      final (playing, processingState, sequenceLength) = snapshot.data ?? (false, ProcessingState.idle, 0);
      final busy = processingState == ProcessingState.loading || processingState == ProcessingState.buffering;
      final hasSource = sequenceLength > 0;
      final IconData icon;
      final String tooltip;
      final VoidCallback? onPressed;
      if (playing && processingState == ProcessingState.completed) {
        icon = Icons.replay_rounded;
        tooltip = 'Replay';
        onPressed = hasSource ? (onReplay ?? () => unawaited(player.seek(Duration.zero))) : null;
      } else if (playing) {
        icon = Icons.pause_rounded;
        tooltip = 'Pause';
        onPressed = () => unawaited(player.pause());
      } else {
        icon = Icons.play_arrow_rounded;
        tooltip = 'Play';
        onPressed = hasSource && !busy ? () => unawaited(player.play()) : null;
      }
      return SizedBox.square(
        dimension: size + 12,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (busy) SizedBox.square(dimension: size + 10, child: const CircularProgressIndicator(strokeWidth: 3)),
            SizedBox.square(
              dimension: size,
              child: IconButton.filled(
                tooltip: tooltip,
                iconSize: size * 0.55,
                onPressed: onPressed,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(icon, key: ValueKey(icon)),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Skips to the previous item; disabled when there is none.
class SkipPreviousButton extends StatelessWidget {
  const new(this.player, {super.key});

  /// The player to control.
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => StreamBuilder<SequenceState?>(
    stream: player.sequenceStateStream,
    builder: (context, snapshot) => IconButton(
      tooltip: 'Previous',
      iconSize: 36,
      icon: const Icon(Icons.skip_previous_rounded),
      onPressed: player.hasPrevious ? () => unawaited(player.seekToPrevious()) : null,
    ),
  );
}

/// Skips to the next item; disabled when there is none.
class SkipNextButton extends StatelessWidget {
  const new(this.player, {super.key});

  /// The player to control.
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => StreamBuilder<SequenceState?>(
    stream: player.sequenceStateStream,
    builder: (context, snapshot) => IconButton(
      tooltip: 'Next',
      iconSize: 36,
      icon: const Icon(Icons.skip_next_rounded),
      onPressed: player.hasNext ? () => unawaited(player.seekToNext()) : null,
    ),
  );
}

/// Seeks by [offset] relative to the current position, staying within the item.
class SeekByButton extends StatelessWidget {
  const new(this.player, {super.key, required this.offset});

  /// The player to control.
  final AudioPlayer player;

  /// How far to seek; negative values seek backwards.
  final Duration offset;

  @override
  Widget build(BuildContext context) {
    final forward = offset > Duration.zero;
    return IconButton(
      tooltip: '${forward ? 'Forward' : 'Back'} ${offset.inSeconds.abs()} seconds',
      iconSize: 30,
      icon: Icon(forward ? Icons.forward_10_rounded : Icons.replay_10_rounded),
      onPressed: () {
        final duration = player.duration;
        var target = player.position + offset;
        if (target < Duration.zero) {
          target = Duration.zero;
        }
        if (duration != null && target > duration) {
          target = duration;
        }
        unawaited(player.seek(target));
      },
    );
  }
}

/// Stops playback and releases the native player's resources.
class StopButton extends StatelessWidget {
  const new(this.player, {super.key});

  /// The player to control.
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Stop',
    iconSize: 30,
    icon: const Icon(Icons.stop_rounded),
    onPressed: () => unawaited(player.stop()),
  );
}

/// Toggles shuffle mode. A fresh shuffle order is generated each time shuffle is turned on.
class ShuffleButton extends StatelessWidget {
  const new(this.player, {super.key});

  /// The player to control.
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: player.shuffleModeEnabledStream,
    builder: (context, snapshot) {
      final enabled = snapshot.data ?? false;
      return IconButton(
        tooltip: enabled ? 'Shuffle on' : 'Shuffle off',
        isSelected: enabled,
        icon: const Icon(Icons.shuffle_rounded),
        selectedIcon: const Icon(Icons.shuffle_on_rounded),
        onPressed: () async {
          final enable = !enabled;
          if (enable) {
            await player.shuffle();
          }
          await player.setShuffleModeEnabled(enabled: enable);
        },
      );
    },
  );
}

/// Cycles the loop mode: off → all → one.
class LoopButton extends StatelessWidget {
  const new(this.player, {super.key});

  /// The player to control.
  final AudioPlayer player;

  static const _cycle = [LoopMode.off, LoopMode.all, LoopMode.one];

  @override
  Widget build(BuildContext context) => StreamBuilder<LoopMode>(
    stream: player.loopModeStream,
    builder: (context, snapshot) {
      final loopMode = snapshot.data ?? LoopMode.off;
      final (icon, tooltip) = switch (loopMode) {
        LoopMode.off => (Icons.repeat_rounded, 'Loop off'),
        LoopMode.all => (Icons.repeat_on_rounded, 'Loop all'),
        LoopMode.one => (Icons.repeat_one_on_rounded, 'Loop one'),
      };
      return IconButton(
        tooltip: tooltip,
        isSelected: loopMode != LoopMode.off,
        icon: Icon(icon),
        onPressed: () => unawaited(player.setLoopMode(_cycle[(_cycle.indexOf(loopMode) + 1) % _cycle.length])),
      );
    },
  );
}
