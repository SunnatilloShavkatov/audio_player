import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

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

  /// Collects the data useful for displaying in a seek bar, using a handy
  /// feature of rx_dart to combine the 3 streams of interest into one.
  Stream<PositionData> get _positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
    _player.positionStream,
    _player.bufferedPositionStream,
    _player.durationStream,
    (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Audio Player',
    home: Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Display play/pause button and volume/speed sliders.
            ControlButtons(_player),
            // Display seek bar. Using StreamBuilder, this widget rebuilds
            // each time the position, buffered position or duration changes.
            StreamBuilder<PositionData>(
              stream: _positionDataStream,
              builder: (context, snapshot) {
                final positionData = snapshot.data;
                return SeekBar(
                  duration: positionData?.duration ?? Duration.zero,
                  position: positionData?.position ?? Duration.zero,
                  bufferedPosition: positionData?.bufferedPosition ?? Duration.zero,
                  onChangeEnd: _player.seek,
                );
              },
            ),
          ],
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
      // Opens volume slider dialog
      IconButton(
        icon: const Icon(Icons.volume_up),
        onPressed: () {
          showSliderDialog(
            context: context,
            title: 'Adjust volume',
            divisions: 10,
            min: 0,
            max: 1,
            stream: player.volumeStream,
            onChanged: player.setVolume,
          );
        },
      ),

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
      IconButton(icon: const Icon(Icons.stop), iconSize: 64, onPressed: player.stop),
      // Opens speed slider dialog
      StreamBuilder<double>(
        stream: player.speedStream,
        builder: (context, snapshot) => IconButton(
          icon: Text('${snapshot.data?.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () {
            showSliderDialog(
              context: context,
              title: 'Adjust speed',
              divisions: 10,
              min: 0.5,
              max: 1.5,
              stream: player.speedStream,
              onChanged: player.setSpeed,
            );
          },
        ),
      ),
    ],
  );
}
