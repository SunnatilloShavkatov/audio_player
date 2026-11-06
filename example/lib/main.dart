import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const new({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _player = AudioPlayer();

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
    // Listen to errors during playback.
    _player.errorStream.listen((e) {
      debugPrint('A stream error occurred: $e');
    });
    // Try to load audio from a source and catch any errors.
    try {
      // AAC example: https://dl.espressif.com/dl/audio/ff-16b-2c-44100hz.aac
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
    // Release decoders and buffers back to the operating system making them
    // available for other apps to use.
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
    title: 'Audio Player',
    home: Scaffold(
      appBar: AppBar(title: const Text('Audio Player')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  const NowPlaying(title: 'A Salute To Head-Scratching Science', subtitle: 'Science Friday'),
                  const SizedBox(height: 24),
                  // Rebuilds each time the position, buffered position or duration changes.
                  PlayerSeekBar(_player),
                  const SizedBox(height: 12),
                  TransportControls(
                    _player,
                    leading: [
                      StopButton(_player),
                      SeekByButton(_player, offset: const Duration(seconds: -10)),
                    ],
                    trailing: [
                      SeekByButton(_player, offset: const Duration(seconds: 10)),
                      LoopButton(_player),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Volume, speed and pitch open in a bottom sheet.
                  PlaybackSettingsBar(_player),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
