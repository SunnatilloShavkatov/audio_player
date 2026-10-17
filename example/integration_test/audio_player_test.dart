// Runs the plugin's native players (Media3 on Android, AVQueuePlayer on iOS
// and macOS) on a real device, simulator or desktop:
//
//   cd example && flutter test integration_test -d <device>
//
// The tests play a bundled 3 second tone, so they need no network access.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _tone = 'assets/audio/tone.wav';
const _toneDuration = Duration(seconds: 3);

/// How long to wait for the native player before failing a test.
const _timeout = Duration(seconds: 15);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AudioPlayer player;

  setUp(() => player = AudioPlayer());
  tearDown(() => player.dispose());

  void expectNear(Duration? actual, Duration expected, {Duration tolerance = const Duration(milliseconds: 200)}) {
    expect(actual, isNotNull, reason: 'expected about $expected');
    expect((actual! - expected).abs(), lessThanOrEqualTo(tolerance), reason: 'expected about $expected, got $actual');
  }

  Future<void> waitForPosition(AudioPlayer player, Duration position) =>
      player.positionStream.firstWhere((p) => p >= position).timeout(_timeout);

  testWidgets('loads an asset and reports its duration', (_) async {
    expectNear(await player.setAsset(_tone).timeout(_timeout), _toneDuration);
    expect(player.processingState, equals(ProcessingState.ready));
    expectNear(player.duration, _toneDuration);
  });

  testWidgets('plays, pauses and resumes', (_) async {
    await player.setAsset(_tone).timeout(_timeout);
    final playing = player.play();
    await waitForPosition(player, const Duration(milliseconds: 500));
    await player.pause();
    await playing.timeout(_timeout);
    expect(player.playing, isFalse);
    final pausedAt = player.position;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expectNear(player.position, pausedAt, tolerance: const Duration(milliseconds: 50));

    unawaited(player.play());
    await waitForPosition(player, pausedAt + const Duration(milliseconds: 300));
    await player.pause();
  });

  testWidgets('play() completes when playback completes', (_) async {
    await player.setAsset(_tone, initialPosition: const Duration(milliseconds: 2500)).timeout(_timeout);
    await player.play().timeout(_timeout);
    expect(player.processingState, equals(ProcessingState.completed));
    expect(player.playing, isTrue);
  });

  testWidgets('seeks', (_) async {
    await player.setAsset(_tone).timeout(_timeout);
    await player.seek(const Duration(seconds: 2)).timeout(_timeout);
    expectNear(player.position, const Duration(seconds: 2));
    await player.seek(const Duration(milliseconds: 500)).timeout(_timeout);
    expectNear(player.position, const Duration(milliseconds: 500));
  });

  testWidgets('changes volume and speed while playing', (_) async {
    await player.setAsset(_tone).timeout(_timeout);
    unawaited(player.play());
    await player.setVolume(0.5);
    await player.setSpeed(1.5);
    expect(player.volume, equals(0.5));
    expect(player.speed, equals(1.5));
    await waitForPosition(player, const Duration(milliseconds: 500));
    await player.pause();
  });

  testWidgets('clips', (_) async {
    await player.setAsset(_tone).timeout(_timeout);
    final duration = await player
        .setClip(start: const Duration(milliseconds: 500), end: const Duration(milliseconds: 1500))
        .timeout(_timeout);
    expectNear(duration, const Duration(seconds: 1));
    await player.play().timeout(_timeout);
    expect(player.processingState, equals(ProcessingState.completed));
  });

  testWidgets('edits a playlist', (_) async {
    await player
        .setAudioSources([
          AudioSource.asset(_tone, tag: 'a'),
          AudioSource.asset(_tone, tag: 'b'),
          AudioSource.asset(_tone, tag: 'c'),
        ])
        .timeout(_timeout);
    List<Object?> tags() => player.sequence.map((source) => source.tag).toList();
    Future<void> waitForIndex(int index) => player.currentIndexStream.firstWhere((i) => i == index).timeout(_timeout);

    expect(player.currentIndex, equals(0));
    await player.seekToNext();
    await waitForIndex(1);

    await player.addAudioSource(AudioSource.asset(_tone, tag: 'd'));
    expect(tags(), equals(['a', 'b', 'c', 'd']));
    // Moving an item in front of the current one shifts the current index.
    await player.moveAudioSource(3, 0);
    expect(tags(), equals(['d', 'a', 'b', 'c']));
    await waitForIndex(2);
    await player.removeAudioSourceAt(0);
    expect(tags(), equals(['a', 'b', 'c']));
    await waitForIndex(1);
    await player.insertAudioSources(0, [AudioSource.asset(_tone, tag: 'e'), AudioSource.asset(_tone, tag: 'f')]);
    await waitForIndex(3);
    await player.removeAudioSourceRange(0, 2);
    await waitForIndex(1);

    await player.setShuffleModeEnabled(enabled: true);
    await player.shuffle();
    await player.setLoopMode(LoopMode.all);
    expect(player.shuffleModeEnabled, isTrue);
    expect(player.loopMode, equals(LoopMode.all));
    final playing = player.play();
    await waitForPosition(player, const Duration(milliseconds: 300));
    await player.pause();
    await playing.timeout(_timeout);
  });

  testWidgets('advances in the current shuffle order', (_) async {
    await player
        .setAudioSources([
          for (final tag in ['a', 'b', 'c', 'd', 'e']) AudioSource.asset(_tone, tag: tag),
        ], shuffleOrder: DefaultShuffleOrder(random: Random(1)))
        .timeout(_timeout);
    await player.setShuffleModeEnabled(enabled: true);
    // Reshuffle until the item after the current one changes, so that the
    // platform player only advances to it if it received the new order.
    final loadedNextIndex = player.nextIndex;
    for (var i = 0; i < 20 && player.nextIndex == loadedNextIndex; i++) {
      await player.shuffle();
    }
    final expectedNextIndex = player.nextIndex;
    expect(expectedNextIndex, isNot(equals(loadedNextIndex)));
    final currentIndex = player.currentIndex;
    await player.seek(const Duration(milliseconds: 2700)).timeout(_timeout);
    unawaited(player.play());
    expect(
      await player.currentIndexStream.firstWhere((i) => i != currentIndex).timeout(_timeout),
      equals(expectedNextIndex),
    );
    await player.pause();
  });

  testWidgets('reports a missing file and recovers', (_) async {
    await expectLater(
      player.setFilePath('${Directory.systemTemp.path}/audio_player_missing.wav').timeout(_timeout),
      throwsA(isA<PlayerException>()),
    );
    expectNear(await player.setAsset(_tone).timeout(_timeout), _toneDuration);
  });

  testWidgets('stops, releasing the native player, and reloads', (_) async {
    await player.setAsset(_tone).timeout(_timeout);
    await player.seek(const Duration(seconds: 1)).timeout(_timeout);
    await player.stop();
    expect(player.processingState, equals(ProcessingState.idle));
    expectNear(await player.load().timeout(_timeout), _toneDuration);
    expectNear(player.position, const Duration(seconds: 1));
  });

  testWidgets('plays two players at once', (_) async {
    final other = AudioPlayer();
    addTearDown(other.dispose);
    await player.setAsset(_tone).timeout(_timeout);
    await other.setAsset(_tone).timeout(_timeout);
    unawaited(player.play());
    unawaited(other.play());
    await Future.wait([
      waitForPosition(player, const Duration(milliseconds: 500)),
      waitForPosition(other, const Duration(milliseconds: 500)),
    ]);
    await player.pause();
    await other.pause();
  });

  testWidgets('applies Android audio effects, and ignores them elsewhere', (_) async {
    final equalizer = AndroidEqualizer();
    final loudnessEnhancer = AndroidLoudnessEnhancer();
    final effectsPlayer = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, loudnessEnhancer]));
    addTearDown(effectsPlayer.dispose);
    expectNear(await effectsPlayer.setAsset(_tone).timeout(_timeout), _toneDuration);
    await equalizer.setEnabled(enabled: true);
    await loudnessEnhancer.setEnabled(enabled: true);
    await loudnessEnhancer.setTargetGain(0.5);
    if (Platform.isAndroid) {
      final parameters = await equalizer.parameters.timeout(_timeout);
      expect(parameters.bands, isNotEmpty);
      await parameters.bands.first.setGain(parameters.minDecibels);
    }
    final playing = effectsPlayer.play();
    await waitForPosition(effectsPlayer, const Duration(milliseconds: 300));
    await effectsPlayer.pause();
    await playing.timeout(_timeout);
  });
}
