import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.black));
    unawaited(_init());
  }

  Future<void> _init() async {
    // Inform the operating system of our app's audio attributes etc.
    // We pick a reasonable default for an app that plays speech.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    // Listen to errors during playback.
    _player.errorStream.listen((e) {
      debugPrint('A stream error occurred: $e');
    });
    // Try to load audio from a source and catch any errors.
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse('https://stream-uk1.radioparadise.com/aac-320')));
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
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StreamBuilder<IcyMetadata?>(
                stream: _player.icyMetadataStream,
                builder: (context, snapshot) {
                  final metadata = snapshot.data;
                  final title = metadata?.info?.title ?? '';
                  final url = metadata?.info?.url;
                  return Column(
                    children: [
                      if (url != null) Image.network(url),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                      ),
                    ],
                  );
                },
              ),
              // Display play/pause button and volume/speed sliders.
              ControlButtons(_player),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Displays the play/pause button and volume/speed sliders.
class ControlButtons extends StatelessWidget {
  const new(this.player, {super.key});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      /// This StreamBuilder rebuilds whenever the player state changes, which
      /// includes the playing/paused state and also the
      /// loading/buffering/ready state. Depending on the state we show the
      /// appropriate button or loading indicator.
      StreamBuilder<PlayerState>(
        stream: player.playerStateStream,
        builder: (context, snapshot) {
          final playerState = snapshot.data;
          final processingState = playerState?.processingState;
          final playing = playerState?.playing;
          if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
            return Container(
              margin: const EdgeInsets.all(8),
              width: 64,
              height: 64,
              child: const CircularProgressIndicator(),
            );
          } else if (playing != true) {
            return IconButton(icon: const Icon(Icons.play_arrow), iconSize: 64, onPressed: player.play);
          } else if (processingState != ProcessingState.completed) {
            return IconButton(icon: const Icon(Icons.pause), iconSize: 64, onPressed: player.pause);
          } else {
            return IconButton(
              icon: const Icon(Icons.replay),
              iconSize: 64,
              onPressed: () => player.seek(Duration.zero),
            );
          }
        },
      ),
    ],
  );
}
