import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:material_ui/material_ui.dart';

/// Card header with an icon, title, subtitle and an on/off switch bound to [enabledStream].
class _EffectHeader extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabledStream,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Stream<bool> enabledStream;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<bool>(
      stream: enabledStream,
      builder: (context, snapshot) => SwitchListTile(
        secondary: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle),
        value: snapshot.data ?? false,
        onChanged: onChanged,
      ),
    );
  }
}

/// Switch and target gain slider for an [AndroidLoudnessEnhancer].
class LoudnessEnhancerCard extends StatelessWidget {
  const new({super.key, required this.loudnessEnhancer});

  /// The effect to control.
  final AndroidLoudnessEnhancer loudnessEnhancer;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _EffectHeader(
            icon: Icons.campaign_rounded,
            title: 'Loudness enhancer',
            subtitle: 'Boosts the signal to a target gain · Android only',
            enabledStream: loudnessEnhancer.enabledStream,
            onChanged: (enabled) => unawaited(loudnessEnhancer.setEnabled(enabled: enabled)),
          ),
          StreamBuilder<double>(
            stream: loudnessEnhancer.targetGainStream,
            builder: (context, snapshot) {
              final targetGain = snapshot.data ?? 0.0;
              final theme = Theme.of(context);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Slider(
                        min: -1,
                        value: targetGain.clamp(-1, 1),
                        label: '${targetGain.toStringAsFixed(2)} dB',
                        onChanged: (gain) => unawaited(loudnessEnhancer.setTargetGain(gain)),
                      ),
                    ),
                    SizedBox(
                      width: 72,
                      child: Text(
                        '${targetGain.toStringAsFixed(2)} dB',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Switch and one vertical gain slider per band for an [AndroidEqualizer].
class EqualizerCard extends StatelessWidget {
  const new({super.key, required this.equalizer});

  /// The effect to control.
  final AndroidEqualizer equalizer;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _EffectHeader(
            icon: Icons.equalizer_rounded,
            title: 'Equalizer',
            subtitle: 'Per-band gain · Android only',
            enabledStream: equalizer.enabledStream,
            onChanged: (enabled) => unawaited(equalizer.setEnabled(enabled: enabled)),
          ),
          SizedBox(height: 240, child: _EqualizerBands(equalizer: equalizer)),
        ],
      ),
    ),
  );
}

class _EqualizerBands extends StatelessWidget {
  const new({required this.equalizer});

  final AndroidEqualizer equalizer;

  @override
  Widget build(BuildContext context) => FutureBuilder<AndroidEqualizerParameters>(
    future: equalizer.parameters,
    builder: (context, snapshot) {
      final theme = Theme.of(context);
      final parameters = snapshot.data;
      if (parameters == null || parameters.bands.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              snapshot.hasError
                  ? 'The equalizer is not available on this platform.'
                  : 'Bands appear once the player is ready.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        );
      }
      final labelStyle = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Row(
          children: [
            for (final band in parameters.bands)
              Expanded(
                child: StreamBuilder<double>(
                  stream: band.gainStream,
                  builder: (context, snapshot) {
                    final gain = snapshot.data ?? band.gain;
                    return Column(
                      children: [
                        Text('${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}', style: labelStyle),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              min: parameters.minDecibels,
                              max: parameters.maxDecibels,
                              value: gain.clamp(parameters.minDecibels, parameters.maxDecibels),
                              onChanged: (gain) => unawaited(band.setGain(gain)),
                            ),
                          ),
                        ),
                        Text(_formatFrequency(band.centerFrequency), style: labelStyle),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

String _formatFrequency(double hertz) =>
    hertz >= 1000 ? '${(hertz / 1000).toStringAsFixed(hertz >= 10000 ? 0 : 1)} kHz' : '${hertz.round()} Hz';
