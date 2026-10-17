import 'dart:async';

import 'dart:math';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.black));
    unawaited(_init());
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
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

  Stream<PositionData> get _positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
    _player.positionStream,
    _player.bufferedPositionStream,
    _player.durationStream,
    (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<bool>(
              stream: _loudnessEnhancer.enabledStream,
              builder: (context, snapshot) {
                final enabled = snapshot.data ?? false;
                return SwitchListTile(
                  title: const Text('Loudness Enhancer'),
                  value: enabled,
                  onChanged: (enabled) => _loudnessEnhancer.setEnabled(enabled: enabled),
                );
              },
            ),
            LoudnessEnhancerControls(loudnessEnhancer: _loudnessEnhancer),
            StreamBuilder<bool>(
              stream: _equalizer.enabledStream,
              builder: (context, snapshot) {
                final enabled = snapshot.data ?? false;
                return SwitchListTile(
                  title: const Text('Equalizer'),
                  value: enabled,
                  onChanged: (enabled) => _equalizer.setEnabled(enabled: enabled),
                );
              },
            ),
            Expanded(child: EqualizerControls(equalizer: _equalizer)),
            ControlButtons(_player),
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

class LoudnessEnhancerControls extends StatelessWidget {
  const new({super.key, required this.loudnessEnhancer});

  final AndroidLoudnessEnhancer loudnessEnhancer;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    stream: loudnessEnhancer.targetGainStream,
    builder: (context, snapshot) {
      final targetGain = snapshot.data ?? 0.0;
      return Slider(min: -1, value: targetGain, onChanged: loudnessEnhancer.setTargetGain, label: 'foo');
    },
  );
}

class EqualizerControls extends StatelessWidget {
  const new({super.key, required this.equalizer});

  final AndroidEqualizer equalizer;

  @override
  Widget build(BuildContext context) => FutureBuilder<AndroidEqualizerParameters>(
    future: equalizer.parameters,
    builder: (context, snapshot) {
      final parameters = snapshot.data;
      if (parameters == null) {
        return const SizedBox();
      }
      return Row(
        children: [
          for (final band in parameters.bands)
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<double>(
                      stream: band.gainStream,
                      builder: (context, snapshot) => VerticalSlider(
                        min: parameters.minDecibels,
                        max: parameters.maxDecibels,
                        value: band.gain,
                        onChanged: band.setGain,
                      ),
                    ),
                  ),
                  Text('${band.centerFrequency.round()} Hz'),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class VerticalSlider extends StatelessWidget {
  const new({super.key, required this.value, this.min = 0.0, this.max = 1.0, this.onChanged});

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.fitHeight,
    alignment: Alignment.bottomCenter,
    child: Transform.rotate(
      angle: -pi / 2,
      child: Container(
        width: 400,
        height: 400,
        alignment: Alignment.center,
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      ),
    ),
  );
}

class ControlButtons extends StatelessWidget {
  const new(this.player, {super.key});

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
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
