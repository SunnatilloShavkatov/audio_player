import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rxdart/rxdart.dart';

/// Chips showing the current volume, speed and pitch. Tapping one opens [showPlaybackSettingsSheet].
class PlaybackSettingsBar extends StatelessWidget {
  const new(this.player, {super.key, this.showSpeed = true, this.showPitch = true});

  /// The player to show and control.
  final AudioPlayer player;

  /// Whether to show the speed chip and slider.
  final bool showSpeed;

  /// Whether to show the pitch chip and slider.
  final bool showPitch;

  void _open(BuildContext context) =>
      showPlaybackSettingsSheet(context: context, player: player, showSpeed: showSpeed, showPitch: showPitch);

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      _ValueChip(
        stream: player.volumeStream,
        icon: _volumeIcon,
        label: (volume) => '${(volume * 100).round()}%',
        tooltip: 'Volume',
        onPressed: () => _open(context),
      ),
      if (showSpeed)
        _ValueChip(
          stream: player.speedStream,
          icon: (_) => Icons.speed_rounded,
          label: (speed) => '${speed.toStringAsFixed(1)}×',
          tooltip: 'Speed',
          onPressed: () => _open(context),
        ),
      if (showPitch)
        _ValueChip(
          stream: player.pitchStream,
          icon: (_) => Icons.graphic_eq_rounded,
          label: (pitch) => 'Pitch ${pitch.toStringAsFixed(1)}',
          tooltip: 'Pitch',
          onPressed: () => _open(context),
        ),
    ],
  );
}

IconData _volumeIcon(double volume) => switch (volume) {
  <= 0 => Icons.volume_off_rounded,
  < 0.5 => Icons.volume_down_rounded,
  _ => Icons.volume_up_rounded,
};

class _ValueChip extends StatelessWidget {
  const new({
    required this.stream,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final ValueStream<double> stream;
  final IconData Function(double value) icon;
  final String Function(double value) label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    stream: stream,
    initialData: stream.valueOrNull,
    builder: (context, snapshot) {
      final value = snapshot.data ?? 1.0;
      return ActionChip(tooltip: tooltip, avatar: Icon(icon(value)), label: Text(label(value)), onPressed: onPressed);
    },
  );
}

/// Opens a bottom sheet with cards for the volume, speed and pitch of [player].
void showPlaybackSettingsSheet({
  required BuildContext context,
  required AudioPlayer player,
  bool showSpeed = true,
  bool showPitch = true,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text('Playback', style: Theme.of(context).textTheme.titleLarge),
            SliderSettingCard(
              icon: Icons.volume_up_rounded,
              title: 'Volume',
              stream: player.volumeStream,
              min: 0,
              max: 1,
              divisions: 10,
              defaultValue: 1,
              format: (volume) => '${(volume * 100).round()}%',
              onChanged: player.setVolume,
            ),
            if (showSpeed)
              SliderSettingCard(
                icon: Icons.speed_rounded,
                title: 'Speed',
                stream: player.speedStream,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                defaultValue: 1,
                format: (speed) => '${speed.toStringAsFixed(1)}×',
                onChanged: player.setSpeed,
              ),
            if (showPitch)
              SliderSettingCard(
                icon: Icons.graphic_eq_rounded,
                title: 'Pitch',
                subtitle: 'Android only',
                stream: player.pitchStream,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                defaultValue: 1,
                format: (pitch) => pitch.toStringAsFixed(1),
                onChanged: player.setPitch,
              ),
          ],
        ),
      ),
    ),
  );
}

/// A card with a titled slider bound to [stream], a value read-out and a reset button.
class SliderSettingCard extends StatelessWidget {
  const new({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.stream,
    required this.min,
    required this.max,
    this.divisions,
    required this.defaultValue,
    required this.format,
    required this.onChanged,
  });

  /// Leading icon.
  final IconData icon;

  /// Name of the setting.
  final String title;

  /// Optional hint under the title.
  final String? subtitle;

  /// Current value of the setting.
  final ValueStream<double> stream;

  /// Slider minimum.
  final double min;

  /// Slider maximum.
  final double max;

  /// Number of discrete slider steps.
  final int? divisions;

  /// Value the reset button restores.
  final double defaultValue;

  /// Formats the value for the read-out.
  final String Function(double value) format;

  /// Applies a new value.
  final Future<void> Function(double value) onChanged;

  void _set(double value) => unawaited(onChanged(value).catchError((Object e) => debugPrint('$title: $e')));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: StreamBuilder<double>(
          stream: stream,
          initialData: stream.valueOrNull,
          builder: (context, snapshot) {
            final value = (snapshot.data ?? defaultValue).clamp(min, max);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      format(value),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reset',
                      icon: const Icon(Icons.restart_alt_rounded),
                      onPressed: value == defaultValue ? null : () => _set(defaultValue),
                    ),
                  ],
                ),
                Slider(min: min, max: max, divisions: divisions, value: value, label: format(value), onChanged: _set),
              ],
            );
          },
        ),
      ),
    );
  }
}
