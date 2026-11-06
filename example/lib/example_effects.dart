import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:audio_player_example/ui/effects_cards.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const new({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _equalizer = AndroidEqualizer();
  final _loudnessEnhancer = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_loudnessEnhancer, _equalizer]),
  );

  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    unawaited(_init());
  }

  Future<void> _init() async {
    // Inform the operating system of our app's audio attributes.
    // We pick a reasonable default for an app that plays speech.
    await _player.setAndroidAudioAttributes(
      const AndroidAudioAttributes(contentType: AndroidAudioContentType.speech, usage: AndroidAudioUsage.media),
    );
    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse('https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3')),
      );
    } on PlayerException catch (e) {
      debugPrint('Error loading audio source: $e');
    }
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release the player's resources when not in use. We use "stop" so that
      // if the app resumes later, it will still remember what position to
      // resume from.
      unawaited(_player.stop());
    }
  }

  @override
  Widget build(BuildContext context) => DemoApp(
    title: 'Audio effects',
    home: Scaffold(
      appBar: AppBar(title: const Text('Audio effects')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _MiniPlayerCard(_player),
                const SizedBox(height: 16),
                LoudnessEnhancerCard(loudnessEnhancer: _loudnessEnhancer),
                const SizedBox(height: 16),
                EqualizerCard(equalizer: _equalizer),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Compact player: small artwork with the title, seek bar, transport controls and playback settings.
class _MiniPlayerCard extends StatelessWidget {
  const new(this.player);

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                const Artwork(size: 64, radius: 14),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('A Salute To Head-Scratching Science', style: theme.textTheme.titleMedium, maxLines: 2),
                      Text(
                        'Science Friday',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PlayerSeekBar(player),
            TransportControls(
              player,
              leading: [
                StopButton(player),
                SeekByButton(player, offset: const Duration(seconds: -10)),
              ],
              trailing: [
                SeekByButton(player, offset: const Duration(seconds: 10)),
                LoopButton(player),
              ],
            ),
            const SizedBox(height: 12),
            PlaybackSettingsBar(player),
          ],
        ),
      ),
    );
  }
}
