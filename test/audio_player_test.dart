import 'dart:async';
import 'dart:math';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player/src/audio_player.dart' show AudioPlayerTestHooks;
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runTests();
}

void runTests() {
  final mock = MockAudioPlayerPlatform();
  AudioPlayerPlatform.instance = mock;

  void expectDuration(Duration a, Duration b, {int epsilon = 30}) {
    expect((a - b).inMilliseconds.abs(), lessThanOrEqualTo(epsilon));
  }

  void expectState({required AudioPlayer player, Duration? position, ProcessingState? processingState, bool? playing}) {
    if (position != null) {
      expectDuration(player.position, position);
    }
    if (processingState != null) {
      expect(player.processingState, equals(processingState));
    }
    if (playing != null) {
      expect(player.playing, equals(playing));
    }
  }

  void checkIndices(List<int> indices, int length) {
    expect(indices.length, length);
    final sorted = List.of(indices)..sort();
    expect(sorted, equals(List.generate(indices.length, (i) => i)));
  }

  // These tests run on the development machine; behave as on Android, where
  // all of the player's features are available.
  setUpAll(() => AudioPlayerTestHooks.testTargetPlatform = TargetPlatform.android);
  tearDownAll(() => AudioPlayerTestHooks.testTargetPlatform = null);

  test('init', () async {
    final player = AudioPlayer();
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.position, equals(Duration.zero));
    //expect(player.bufferedPosition, equals(Duration.zero));
    expect(player.duration, equals(null));
    expect(player.icyMetadata, equals(null));
    expect(player.currentIndex, equals(null));
    expect(player.androidAudioSessionId, equals(null));
    expect(player.playing, equals(false));
    expect(player.volume, equals(1.0));
    expect(player.speed, equals(1.0));
    expect(player.sequence, equals([]));
    expect(player.hasNext, equals(false));
    expect(player.hasPrevious, equals(false));
    //expect(player.loopMode, equals(LoopMode.off));
    //expect(player.shuffleModeEnabled, equals(false));
    expect(player.automaticallyWaitsToMinimizeStalling, equals(true));
    await player.dispose();
  });

  test('assets', () async {
    final player = AudioPlayer();
    void expectAsset(String uri, {Object? tag}) {
      final audioSource = player.audioSource;
      expect(audioSource is UriAudioSource && audioSource.uri.toString() == uri, equals(true));
      expect(audioSource is UriAudioSource && audioSource.tag == tag, equals(true));
    }

    await player.setAsset('audio/foo.mp3', preload: false);
    expectAsset('asset:///audio/foo.mp3');
    await player.setAsset('audio/foo.mp3', package: 'bar', preload: false);
    expectAsset('asset:///packages/bar/audio/foo.mp3');
    await player.setAudioSource(AudioSource.asset('audio/foo.mp3'), preload: false);
    expectAsset('asset:///audio/foo.mp3');
    await player.setAudioSource(AudioSource.asset('audio/foo.mp3', package: 'bar', tag: 'asset-tag'), preload: false);
    expectAsset('asset:///packages/bar/audio/foo.mp3', tag: 'asset-tag');
  });

  test('idle-state', () async {
    final player = AudioPlayer();
    unawaited(player.play());
    expectState(player: player, playing: true);
    await player.pause();
    expectState(player: player, playing: false);
    await player.setVolume(0.5);
    expect(player.volume, equals(0.5));
    await player.setSpeed(0.7);
    expect(player.speed, equals(0.7));
    await player.setLoopMode(LoopMode.one);
    expect(player.loopMode, equals(LoopMode.one));
    await player.setShuffleModeEnabled(enabled: true);
    expect(player.shuffleModeEnabled, equals(true));
    await player.seek(const Duration(seconds: 1));
    expectState(player: player, playing: false, position: const Duration(seconds: 1));
    await player.setAudioSources([], preload: false);
    final audioSources = [
      AudioSource.uri(Uri.parse('https://foo.foo/foo.mp3'), tag: 'a'),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3'), tag: 'b'),
      AudioSource.uri(Uri.parse('https://baz.baz/baz.mp3'), tag: 'c'),
    ];
    await player.addAudioSources(audioSources);
    await player.moveAudioSource(2, 1);
    await player.removeAudioSourceAt(2);
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.sequence.map((s) => s.tag as String?).toList(), equals(['a', 'c']));
    await player.clearAudioSources();
    await player.addAudioSources(audioSources);
    await player.moveAudioSource(2, 1);
    await player.removeAudioSourceAt(2);
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.sequence.map((s) => s.tag as String?).toList(), equals(['a', 'c']));
    await player.dispose();
  });

  test('load', () async {
    final player = AudioPlayer();
    final duration = await player.setUrl('https://foo.foo/foo.mp3');
    expect(duration, equals(audioSourceDuration));
    expect(player.duration, equals(duration));
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.position, equals(Duration.zero));
    expect(player.currentIndex, equals(0));
    expect(player.hasNext, equals(false));
    expect(player.hasPrevious, equals(false));
    expect(player.sequence.length, equals(1));
    expect(player.playing, equals(false));
    await player.dispose();
  });

  test('initial-seek-values', () async {
    final player = AudioPlayer();
    const targetPos = Duration(seconds: 2);
    await player.setAudioSources(
      [AudioSource.uri(Uri.parse('https://a.a/a.mp3')), AudioSource.uri(Uri.parse('https://b.b/b.mp3'))],
      initialPosition: targetPos,
      initialIndex: 1,
    );
    expect(player.position, targetPos);
    expect(player.currentIndex, 1);
    await player.stop();
    await player.load();
    expect(player.position, targetPos);
    expect(player.currentIndex, 1);
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://a.a/a.mp3')),
      AudioSource.uri(Uri.parse('https://b.b/b.mp3')),
    ]);
    expect(player.position, equals(Duration.zero));
    expect(player.currentIndex, 0);
    await player.dispose();
  });

  test('load error', () async {
    final player = AudioPlayer();
    Object? exception;
    try {
      await player.setUrl('https://foo.foo/404.mp3');
      exception = null;
    } catch (e) {
      exception = e;
    }
    expect(exception != null, equals(true));
    try {
      await player.setUrl('https://foo.foo/abort.mp3');
      exception = null;
    } catch (e) {
      exception = e;
    }
    expect(exception != null, equals(true));
    try {
      await player.setUrl('https://foo.foo/error.mp3');
      exception = null;
    } catch (e) {
      exception = e;
    }
    expect(exception != null, equals(true));
    await player.dispose();
  });

  test('control', () async {
    final player = AudioPlayer();
    final duration = (await player.setUrl('https://foo.foo/foo.mp3'))!;
    final point1 = duration * 0.3;
    expectState(player: player, position: Duration.zero, processingState: ProcessingState.ready, playing: false);
    await player.seek(point1);
    expectState(player: player, position: point1, processingState: ProcessingState.ready, playing: false);
    unawaited(player.play());
    expectState(player: player, position: point1, processingState: ProcessingState.ready);
    await Future<dynamic>.delayed(const Duration(milliseconds: 50));
    expectState(player: player, playing: true);
    await Future<dynamic>.delayed(const Duration(milliseconds: 100));
    expectState(
      player: player,
      position: point1 + const Duration(milliseconds: 150),
      processingState: ProcessingState.ready,
      playing: true,
    );
    const playDuration = Duration(milliseconds: 100);
    final point2 = duration - playDuration;
    await player.seek(point2);
    expectState(player: player, position: point2, processingState: ProcessingState.ready, playing: true);
    await player.pause();
    expectState(player: player, position: point2, processingState: ProcessingState.ready, playing: false);
    final stopwatch = Stopwatch()..start();
    final playFuture = player.play();
    expectState(player: player, position: point2, processingState: ProcessingState.ready);
    expectState(player: player, playing: true);
    await playFuture;
    expectDuration(stopwatch.elapsed, playDuration);
    expectState(player: player, position: duration, processingState: ProcessingState.completed, playing: true);
    await player.dispose();
  });

  test('speed', () async {
    final player = AudioPlayer();
    /*final duration =*/
    await player.setUrl('https://foo.foo/foo.mp3');
    const period1 = Duration(milliseconds: 100);
    const period2 = Duration(milliseconds: 100);
    const speed1 = 0.75;
    const speed2 = 1.5;
    final position1 = period1 * speed1;
    final position2 = position1 + period2 * speed2;
    expectState(player: player, position: Duration.zero);
    await player.setSpeed(speed1);
    unawaited(player.play());
    await Future<dynamic>.delayed(period1);
    expectState(player: player, position: position1);
    await player.setSpeed(speed2);
    await Future<dynamic>.delayed(period2);
    expectState(player: player, position: position2);
    await player.dispose();
  });

  test('skipSilence', () async {
    final player = AudioPlayer();
    expect(player.skipSilenceEnabled, equals(false));
    await player.setSkipSilenceEnabled(enabled: true);
    expect(player.skipSilenceEnabled, equals(true));
    await player.setSkipSilenceEnabled(enabled: false);
    expect(player.skipSilenceEnabled, equals(false));
    await player.dispose();
  });

  test('pitch', () async {
    final player = AudioPlayer();
    expect(player.pitch, equals(1.0));
    await player.setPitch(1.5);
    expect(player.pitch, equals(1.5));
    await player.dispose();
  });

  test('setAutomaticallyWaitsToMinimizeStalling', () async {
    final player = AudioPlayer();
    expect(player.automaticallyWaitsToMinimizeStalling, equals(true));
    await player.setAutomaticallyWaitsToMinimizeStalling(enabled: false);
    expect(player.automaticallyWaitsToMinimizeStalling, equals(false));
    await player.setAutomaticallyWaitsToMinimizeStalling(enabled: true);
    expect(player.automaticallyWaitsToMinimizeStalling, equals(true));
    await player.dispose();
  });

  test('setCanUseNetworkResourcesForLiveStreamingWhilePaused', () async {
    final player = AudioPlayer();
    expect(player.canUseNetworkResourcesForLiveStreamingWhilePaused, equals(false));
    await player.setCanUseNetworkResourcesForLiveStreamingWhilePaused(enabled: true);
    expect(player.canUseNetworkResourcesForLiveStreamingWhilePaused, equals(true));
    await player.setCanUseNetworkResourcesForLiveStreamingWhilePaused(enabled: false);
    expect(player.canUseNetworkResourcesForLiveStreamingWhilePaused, equals(false));
    await player.dispose();
  });

  test('setPreferredPeakBitRate', () async {
    final player = AudioPlayer();
    expect(player.preferredPeakBitRate, equals(0.0));
    await player.setPreferredPeakBitRate(1000);
    expect(player.preferredPeakBitRate, equals(1000.0));
    await player.dispose();
  });

  test('setAllowsExternalPlayback', () async {
    final player = AudioPlayer();
    expect(player.allowsExternalPlayback, equals(false));
    await player.setAllowsExternalPlayback(enabled: true);
    expect(player.allowsExternalPlayback, equals(true));
    await player.dispose();
  });

  test('setAndroidAudioAttributes', () async {
    final player = AudioPlayer();
    await player.setAndroidAudioAttributes(const AndroidAudioAttributes());
    await player.dispose();
  });

  test('setAndroidAudioAttributes reaches the platform before the audio source loads', () async {
    final player = AudioPlayer();
    const attributes = AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      flags: AndroidAudioFlags.audibilityEnforced,
      usage: AndroidAudioUsage.game,
    );
    await player.setAndroidAudioAttributes(attributes);
    await player.setUrl('https://foo.foo/foo.mp3');
    final platform = mock.mostRecentPlayer!;
    expect(platform.androidAudioAttributesRequests, hasLength(1));
    final request = platform.androidAudioAttributesRequests.single;
    expect(request.contentType, equals(AndroidAudioContentType.speech.index));
    expect(request.flags, equals(AndroidAudioFlags.audibilityEnforced.value));
    expect(request.usage, equals(AndroidAudioUsage.game.value));
    // Setting equal attributes again is not sent twice.
    await player.setAndroidAudioAttributes(attributes);
    expect(platform.androidAudioAttributesRequests, hasLength(1));
    await player.setAndroidAudioAttributes(const AndroidAudioAttributes(usage: AndroidAudioUsage.alarm));
    expect(platform.androidAudioAttributesRequests, hasLength(2));
    await player.dispose();
  });

  test('init request asks the platform to handle interruptions and the audio session', () async {
    final player = AudioPlayer();
    await player.setUrl('https://foo.foo/foo.mp3');
    var initRequest = mock.mostRecentPlayer!.initRequest;
    expect(initRequest.handleInterruptions, isTrue);
    expect(initRequest.handleAudioSessionActivation, isTrue);
    expect(initRequest.toMap()['handleInterruptions'], isTrue);
    expect(initRequest.toMap()['handleAudioSessionActivation'], isTrue);
    await player.dispose();

    final manualPlayer = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
    await manualPlayer.setUrl('https://foo.foo/foo.mp3');
    initRequest = mock.mostRecentPlayer!.initRequest;
    expect(initRequest.handleInterruptions, isFalse);
    expect(initRequest.handleAudioSessionActivation, isFalse);
    expect(initRequest.toMap()['handleInterruptions'], isFalse);
    expect(initRequest.toMap()['handleAudioSessionActivation'], isFalse);
    await manualPlayer.dispose();
  });

  test('playing becomes false when the platform pauses on its own', () async {
    final player = AudioPlayer();
    await player.setUrl('https://foo.foo/foo.mp3');
    final platform = mock.mostRecentPlayer!;
    unawaited(player.play());
    await player.playingStream.firstWhere((playing) => playing);
    // For example, the Android audio focus was lost for good.
    platform._broadcastDataMessage(PlayerDataMessage(playing: false));
    await player.playingStream.firstWhere((playing) => !playing);
    expect(player.playing, isFalse);
    // The user can start playback again.
    unawaited(player.play());
    expect(player.playing, isTrue);
    await player.pause();
    await player.dispose();
  });

  test('positionStream', () async {
    final player = AudioPlayer();
    /*final duration =*/
    await player.setUrl('https://foo.foo/foo.mp3');
    const period = Duration(milliseconds: 250);
    const position1 = period;
    final position2 = position1 + period;
    const speed1 = 0.75;
    const speed2 = 1.5;
    final stepDuration = period ~/ 5;
    var target = stepDuration;
    unawaited(player.setSpeed(speed1));
    unawaited(player.play());
    final stopwatch = Stopwatch()..start();

    var completer = Completer<dynamic>();
    late StreamSubscription<Duration> subscription;
    subscription = player.positionStream.listen((position) {
      if (position >= position1) {
        unawaited(subscription.cancel());
        completer.complete();
      } else if (position >= target) {
        expectDuration(position, stopwatch.elapsed * speed1);
        target += stepDuration;
      }
    });
    await completer.future;
    unawaited(player.setSpeed(speed2));
    stopwatch.reset();

    target = position1 + stepDuration;
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      if (position >= position2) {
        unawaited(subscription.cancel());
        completer.complete();
      } else if (position >= target) {
        expectDuration(position, position1 + stopwatch.elapsed * speed2);
        target += stepDuration;
      }
    });
    await completer.future;
    await player.dispose();
  });

  test('icyMetadata', () async {
    final player = AudioPlayer();
    expect(player.icyMetadata, equals(null));
    /*final duration =*/
    await player.setUrl('https://foo.foo/foo.mp3');
    unawaited(player.play());
    expect(player.icyMetadata!.headers!.genre, equals(icyMetadata.headers!.genre));
    expect((await player.icyMetadataStream.first)!.headers!.genre, equals(icyMetadata.headers!.genre));
    await player.dispose();
  });

  test('play completes on pause when the playlist is empty', () async {
    final player = AudioPlayer();
    var completed = false;
    unawaited(player.play().then((_) => completed = true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(player.playing, isTrue);
    expect(completed, isFalse);
    await player.pause();
    await Future<void>.delayed(Duration.zero);
    expect(completed, isTrue);
    await player.dispose();
  });

  test('invalid speed, pitch and volume are rejected', () async {
    final player = AudioPlayer();
    await player.setUrl('https://foo.foo/foo.mp3');
    expect(() => player.setSpeed(0), throwsArgumentError);
    expect(() => player.setPitch(-1), throwsArgumentError);
    expect(() => player.setVolume(-0.1), throwsArgumentError);
    expect(player.speed, equals(1.0));
    expect(player.pitch, equals(1.0));
    expect(player.volume, equals(1.0));
    await player.dispose();
  });

  test('positionStream can be listened to again after cancel', () async {
    final player = AudioPlayer();
    await player.setUrl('https://foo.foo/foo.mp3');
    final stream = player.positionStream;
    for (var i = 0; i < 2; i++) {
      final position = await stream.first;
      expectDuration(position, Duration.zero);
    }
    await player.dispose();
  });

  test('playlist', () async {
    final player = AudioPlayer();
    expect(player.sequence.length, equals(0));
    await player.addAudioSource(AudioSource.uri(Uri.parse('https://b.b/b.mp3'), tag: 'b'));
    await player.load();
    await player.insertAudioSources(
      0,
      List.filled(
        2,
        ClippingAudioSource(
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 65),
          child: AudioSource.uri(Uri.parse('https://foo.foo/foo.mp3')),
          tag: 'a',
        ),
      ),
    );
    await player.insertAudioSource(3, AudioSource.uri(Uri.parse('https://c.c/c.mp3'), tag: 'c'));
    await player.addAudioSources([
      AudioSource.uri(Uri.parse('https://d.d/d.mp3'), tag: 'd'),
      AudioSource.uri(Uri.parse('https://e.e/e.mp3'), tag: 'e'),
    ]);
    await player.insertAudioSources(4, [
      AudioSource.uri(Uri.parse('https://e.e/e.mp3'), tag: 'e'),
      AudioSource.uri(Uri.parse('https://f.f/f.mp3'), tag: 'f'),
    ]);
    expect(player.sequence.map((s) => s.tag as String?), equals(['a', 'a', 'b', 'c', 'e', 'f', 'd', 'e']));
    await player.removeAudioSourceRange(0, 2);
    expect(player.sequence.map((s) => s.tag as String?), equals(['b', 'c', 'e', 'f', 'd', 'e']));
    await player.moveAudioSource(3, 2);
    expect(player.sequence.map((s) => s.tag as String?), equals(['b', 'c', 'f', 'e', 'd', 'e']));
    await player.moveAudioSource(2, 3);
    expect(player.sequence.map((s) => s.tag as String?), equals(['b', 'c', 'e', 'f', 'd', 'e']));
    await player.removeAudioSourceRange(0, 2);
    expect(player.sequence.map((s) => s.tag as String?), equals(['e', 'f', 'd', 'e']));
    await player.removeAudioSourceAt(3);
    expect(player.sequence.map((s) => s.tag as String?), equals(['e', 'f', 'd']));
    await player.removeAudioSourceRange(1, 3);
    expect(player.sequence.map((s) => s.tag as String?), equals(['e']));
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://a.a/a.mp3'), tag: 'a'),
      AudioSource.uri(Uri.parse('https://b.b/b.mp3'), tag: 'b'),
    ]);
    expect(player.sequence.map((s) => s.tag as String?), equals(['a', 'b']));
    await player.clearAudioSources();
    expect(player.sequence.map((s) => s.tag as String?), equals(<String>[]));
    await player.dispose();
  });

  test('idle-playlist', () async {
    final player = AudioPlayer();
    expect(player.sequence.length, equals(0));
    await player.addAudioSource(AudioSource.uri(Uri.parse('https://b.b/b.mp3'), tag: 'b'));
    await player.insertAudioSources(
      0,
      List.filled(
        2,
        ClippingAudioSource(
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 65),
          child: AudioSource.uri(Uri.parse('https://foo.foo/foo.mp3')),
          tag: 'a',
        ),
      ),
    );
    await player.insertAudioSource(3, AudioSource.uri(Uri.parse('https://c.c/c.mp3'), tag: 'c'));
    await player.addAudioSources([
      AudioSource.uri(Uri.parse('https://d.d/d.mp3'), tag: 'd'),
      AudioSource.uri(Uri.parse('https://e.e/e.mp3'), tag: 'e'),
    ]);
    await player.insertAudioSources(4, [
      AudioSource.uri(Uri.parse('https://e.e/e.mp3'), tag: 'e'),
      AudioSource.uri(Uri.parse('https://f.f/f.mp3'), tag: 'f'),
    ]);
    expect(player.sequence.map((s) => s.tag as String?), equals(['a', 'a', 'b', 'c', 'e', 'f', 'd', 'e']));
    await player.removeAudioSourceRange(0, 2);
    expect(player.sequence.map((s) => s.tag as String?), equals(['b', 'c', 'e', 'f', 'd', 'e']));
    await player.moveAudioSource(3, 2);
    expect(player.sequence.map((s) => s.tag as String?), equals(['b', 'c', 'f', 'e', 'd', 'e']));
    await player.moveAudioSource(2, 3);
    expect(player.sequence.map((s) => s.tag as String?), equals(['b', 'c', 'e', 'f', 'd', 'e']));
    await player.removeAudioSourceRange(0, 2);
    expect(player.sequence.map((s) => s.tag as String?), equals(['e', 'f', 'd', 'e']));
    await player.removeAudioSourceAt(3);
    expect(player.sequence.map((s) => s.tag as String?), equals(['e', 'f', 'd']));
    await player.removeAudioSourceRange(1, 3);
    expect(player.sequence.map((s) => s.tag as String?), equals(['e']));
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://a.a/a.mp3'), tag: 'a'),
      AudioSource.uri(Uri.parse('https://b.b/b.mp3'), tag: 'b'),
    ], preload: false);
    expect(player.sequence.map((s) => s.tag as String?), equals(['a', 'b']));
    await player.clearAudioSources();
    expect(player.sequence.map((s) => s.tag as String?), equals(<String>[]));
    await player.dispose();
  });

  test('playlist-state', () async {
    final player = AudioPlayer();
    expect(player.sequenceState.sequence, equals([]));
    expect(player.sequenceState.currentIndex, equals(null));
    expect(player.sequenceState.shuffleIndices, equals([]));
    expect(player.sequenceState.shuffleModeEnabled, equals(false));
    expect(player.sequenceState.loopMode, equals(LoopMode.off));
    for (final shuffle in [false, true]) {
      if (shuffle) {
        await player.setShuffleModeEnabled(enabled: shuffle);
      }
      final playlist = [
        AudioSource.uri(Uri.parse('https://bar.bar/a.mp3'), tag: 'a'),
        AudioSource.uri(Uri.parse('https://baz.baz/b.mp3'), tag: 'b'),
        AudioSource.uri(Uri.parse('https://baz.baz/c.mp3'), tag: 'c'),
        AudioSource.uri(Uri.parse('https://baz.baz/d.mp3'), tag: 'd'),
        AudioSource.uri(Uri.parse('https://baz.baz/e.mp3'), tag: 'e'),
      ];
      void expectEffectiveSequence() {
        expect(
          player.sequenceState.effectiveSequence,
          shuffle ? player.effectiveIndices.map((i) => player.sequence[i]).toList() : player.sequence,
        );
      }

      //List<int> effectiveSequenceToIndices() {
      //  return player.effectiveSequence.map((IndexedAudioSource item) => player1.sequence.indexOf(item)).toList();
      //}
      await player.setAudioSources(playlist);
      expect(player.sequenceState.sequence, equals(playlist));
      expect(player.sequenceState.currentIndex, equals(0));
      expect(player.sequenceState.currentSource, equals(playlist[0]));
      expectEffectiveSequence();
      await player.seek(Duration.zero, index: 4);
      expect(player.sequenceState.sequence, equals(playlist));
      expect(player.sequenceState.currentIndex, equals(4));
      expect(player.sequenceState.currentSource, equals(playlist[4]));
      await player.removeAudioSourceAt(4);
      playlist.removeAt(4);
      expectEffectiveSequence();
      expect(player.sequenceState.sequence, equals(playlist));
      expect(player.sequenceState.currentIndex, equals(3));
      expect(player.sequenceState.currentSource, equals(playlist[3]));
      await player.removeAudioSourceAt(1);
      playlist.removeAt(1);
      expect(player.sequenceState.sequence, equals(playlist));
      expect(player.sequenceState.currentIndex, equals(2));
      expect(player.sequenceState.currentSource, equals(playlist[2]));
      await player.clearAudioSources();
      playlist.clear();
      expect(player.sequenceState.sequence, equals(playlist));
      // expecting null here may change in a future version.
      expect(player.sequenceState.currentIndex, equals(null));
      expect(player.sequenceState.currentSource, equals(null));
      expectEffectiveSequence();
    }
    await player.dispose();
  });

  test('setClip', () async {
    final player = AudioPlayer();
    final duration1 = await player.setUrl('https://bar.bar/foo.mp3');
    expectDuration(duration1!, audioSourceDuration);
    final duration2 = await player.setClip(start: const Duration(seconds: 10));
    expectDuration(duration2!, audioSourceDuration - const Duration(seconds: 10));
    final duration3 = await player.setClip(end: const Duration(seconds: 15));
    expectDuration(duration3!, const Duration(seconds: 15));
    final duration4 = await player.setClip(start: const Duration(seconds: 10), end: const Duration(seconds: 21));
    expectDuration(duration4!, const Duration(seconds: 11));
    final duration5 = await player.setClip();
    expectDuration(duration5!, audioSourceDuration);
    await player.dispose();
  });

  test('detect', () {
    expect(AudioSource.uri(Uri.parse('https://a.a/a.mpd')) is DashAudioSource, equals(true));
    expect(AudioSource.uri(Uri.parse('https://a.a/a.m3u8')) is HlsAudioSource, equals(true));
    expect(AudioSource.uri(Uri.parse('https://a.a/a.mp3')) is ProgressiveAudioSource, equals(true));
    expect(AudioSource.uri(Uri.parse('https://a.a/a#.mpd')) is DashAudioSource, equals(true));
  });

  test('shuffle order', () {
    final shuffleOrder1 = DefaultShuffleOrder(random: Random(1001));
    checkIndices(shuffleOrder1.indices, 0);
    //expect(shuffleOrder1.indices, equals([]));
    shuffleOrder1.insert(0, 5);
    //expect(shuffleOrder1.indices, equals([3, 0, 2, 4, 1]));
    checkIndices(shuffleOrder1.indices, 5);
    shuffleOrder1.insert(3, 2);
    checkIndices(shuffleOrder1.indices, 7);
    shuffleOrder1.insert(0, 2);
    checkIndices(shuffleOrder1.indices, 9);
    shuffleOrder1.insert(9, 2);
    checkIndices(shuffleOrder1.indices, 11);

    final indices1 = List.of(shuffleOrder1.indices);
    shuffleOrder1.shuffle();
    expect(shuffleOrder1.indices, isNot(indices1));
    checkIndices(shuffleOrder1.indices, 11);
    final indices2 = List.of(shuffleOrder1.indices);
    shuffleOrder1.shuffle(initialIndex: 5);
    expect(shuffleOrder1.indices[0], equals(5));
    expect(shuffleOrder1.indices, isNot(indices2));
    checkIndices(shuffleOrder1.indices, 11);

    shuffleOrder1.removeRange(4, 6);
    checkIndices(shuffleOrder1.indices, 9);
    shuffleOrder1.removeRange(0, 2);
    checkIndices(shuffleOrder1.indices, 7);
    shuffleOrder1.removeRange(5, 7);
    checkIndices(shuffleOrder1.indices, 5);
    shuffleOrder1.removeRange(0, 5);
    checkIndices(shuffleOrder1.indices, 0);

    shuffleOrder1.insert(0, 5);
    checkIndices(shuffleOrder1.indices, 5);
    shuffleOrder1.clear();
    checkIndices(shuffleOrder1.indices, 0);
  });

  test('shuffle', () async {
    List<AudioSource> createSources() => [
      ...List.filled(
        2,
        ClippingAudioSource(
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 65),
          child: AudioSource.uri(Uri.parse('https://foo.foo/foo.mp3')),
          tag: 'a',
        ),
      ),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3'), tag: 'b'),
      AudioSource.uri(Uri.parse('https://baz.baz/baz.mp3'), tag: 'c'),
      ClippingAudioSource(child: AudioSource.uri(Uri.parse('https://baz.baz/baz.mp3'), tag: 'd')),
    ];
    ShuffleOrder createShuffleOrder() => DefaultShuffleOrder(random: Random(1001));
    final player1 = AudioPlayer();
    await player1.setAudioSources(createSources(), shuffleOrder: createShuffleOrder());
    checkIndices(player1.shuffleIndices, 5);
    expect(player1.shuffleIndices.first, equals(0));
    expect(player1.effectiveIndices, List.generate(player1.sequence.length, (i) => i));
    await player1.seek(Duration.zero, index: 3);
    await player1.shuffle();
    checkIndices(player1.shuffleIndices, 5);
    expect(player1.shuffleIndices.first, equals(3));
    expect(player1.effectiveIndices, List.generate(player1.sequence.length, (i) => i));
    await player1.setShuffleModeEnabled(enabled: true);
    expect(player1.effectiveIndices, player1.shuffleIndices);
    await player1.dispose();

    final player2 = AudioPlayer();
    await player2.setAudioSources(createSources(), initialIndex: 3, shuffleOrder: createShuffleOrder());
    checkIndices(player2.shuffleIndices, 5);
    expect(player2.shuffleIndices.first, equals(3));
    await player2.dispose();
  });

  group('shuffle order lifecycle', () {
    List<AudioSource> createSources() => [
      for (var i = 0; i < 6; i++) AudioSource.uri(Uri.parse('https://foo.foo/$i.mp3'), tag: '$i'),
    ];

    test('the constructor shuffle order is used by setAudioSources', () async {
      final expected = AudioPlayer();
      addTearDown(expected.dispose);
      await expected.setAudioSources(createSources(), shuffleOrder: DefaultShuffleOrder(random: Random(1001)));
      final player = AudioPlayer(shuffleOrder: DefaultShuffleOrder(random: Random(1001)));
      addTearDown(player.dispose);
      await player.setAudioSources(createSources());
      expect(player.shuffleIndices, equals(expected.shuffleIndices));
    });

    test('stop and play keep the shuffle order', () async {
      final player = AudioPlayer(shuffleOrder: DefaultShuffleOrder(random: Random(7)));
      addTearDown(player.dispose);
      await player.setAudioSources(createSources());
      await player.setShuffleModeEnabled(enabled: true);
      await player.seek(Duration.zero, index: 3);
      await player.shuffle();
      final order = [...player.shuffleIndices];
      await player.stop();
      final play = player.play();
      await player.processingStateStream.firstWhere((state) => state == ProcessingState.ready);
      expect(player.shuffleIndices, equals(order));
      await player.pause();
      await play;
    });
  });

  test('seekToIndex', () async {
    final sources = [
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3'), tag: 'foo'),
      AudioSource.uri(Uri.parse('https://baz.baz/bar.mp3'), tag: 'bar'),
      AudioSource.uri(Uri.parse('https://baz.baz/baz.mp3'), tag: 'baz'),
    ];
    final player = AudioPlayer();
    await player.setAudioSources(sources, shuffleOrder: DefaultShuffleOrder(random: Random(1001)));
    expect(player.currentIndex, 0);
    expect(player.hasPrevious, false);
    expect(player.hasNext, true);
    await player.seekToPrevious();
    expect(player.currentIndex, 0);
    await player.seekToNext();
    expect(player.currentIndex, 1);
    expect(player.hasPrevious, true);
    expect(player.hasNext, true);
    await player.seekToNext();
    expect(player.currentIndex, 2);
    expect(player.hasPrevious, true);
    expect(player.hasNext, false);
    await player.seekToNext();
    expect(player.currentIndex, 2);
    await player.seekToPrevious();
    expect(player.currentIndex, 1);
    await player.dispose();
  });

  test('stop', () async {
    final sources = [
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3'), tag: 'foo'),
      AudioSource.uri(Uri.parse('https://baz.baz/bar.mp3'), tag: 'bar'),
    ];
    final player = AudioPlayer();
    expect(player.processingState, ProcessingState.idle);
    await player.setAudioSources(sources, preload: false, shuffleOrder: DefaultShuffleOrder(random: Random(1001)));
    expect(player.processingState, ProcessingState.idle);
    await player.load();
    expect(player.processingState, ProcessingState.ready);
    await player.seek(const Duration(seconds: 5), index: 1);
    await player.setVolume(0.5);
    await player.setSpeed(0.7);
    await player.setShuffleModeEnabled(enabled: true);
    await player.setLoopMode(LoopMode.one);
    await player.stop();
    expect(player.processingState, ProcessingState.idle);
    expect(player.position, const Duration(seconds: 5));
    expect(player.volume, 0.5);
    expect(player.speed, 0.7);
    expect(player.shuffleModeEnabled, true);
    expect(player.loopMode, LoopMode.one);
    await player.load();
    expect(player.processingState, ProcessingState.ready);
    expect(player.position, const Duration(seconds: 5));
    expect(player.volume, 0.5);
    expect(player.speed, 0.7);
    expect(player.shuffleModeEnabled, true);
    expect(player.loopMode, LoopMode.one);
    await player.dispose();
  });

  test('play-load', () async {
    for (final delayMs in [0, 50]) {
      final player = AudioPlayer();
      unawaited(player.play());
      if (delayMs != 0) {
        await Future<dynamic>.delayed(Duration(milliseconds: delayMs));
      }
      expect(player.playing, equals(true));
      expect(player.processingState, equals(ProcessingState.idle));
      await player.setUrl('https://bar.bar/foo.mp3');
      expect(player.processingState, equals(ProcessingState.ready));
      expect(player.playing, equals(true));
      expectDuration(player.position, Duration.zero);
      const playDuration = Duration(milliseconds: 50);
      await Future<dynamic>.delayed(playDuration);
      expectDuration(player.position, playDuration);
      await player.dispose();
    }
  });

  test('play-set', () async {
    for (final delayMs in [0, 50]) {
      final player = AudioPlayer();
      unawaited(player.play());
      if (delayMs != 0) {
        await Future<dynamic>.delayed(Duration(milliseconds: delayMs));
      }
      expect(player.playing, equals(true));
      expect(player.processingState, equals(ProcessingState.idle));
      await player.setUrl('https://bar.bar/foo.mp3', preload: false);
      expect(player.processingState, equals(ProcessingState.ready));
      expect(player.playing, equals(true));
      expectDuration(player.position, Duration.zero);
      const playDuration = Duration(milliseconds: 50);
      await Future<dynamic>.delayed(playDuration);
      expectDuration(player.position, playDuration);
      await player.dispose();
    }
  });

  test('set-play', () async {
    final player = AudioPlayer();
    await player.setUrl('https://bar.bar/foo.mp3', preload: false);
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.playing, equals(false));
    unawaited(player.play());
    expect(player.playing, equals(true));
    await player.processingStateStream.firstWhere((state) => state == ProcessingState.ready);
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.playing, equals(true));
    expectDuration(player.position, Duration.zero);
    const playDuration = Duration(milliseconds: 50);
    await Future<dynamic>.delayed(playDuration);
    expectDuration(player.position, playDuration);
    await player.dispose();
  });

  test('set-set', () async {
    final player = AudioPlayer();
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
    ], preload: false);
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.sequence.length, equals(2));
    expect(player.playing, equals(false));
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/baz.mp3')),
    ], preload: false);
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.sequence.length, equals(3));
    expect(player.playing, equals(false));
    await player.dispose();
  });

  test('load-stop-load-simultaneous', () async {
    final player = AudioPlayer();
    await player.setAudioSource(AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')));
    final stop1Future = player.stop();
    final load1Future = player.setAudioSource(AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')));
    unawaited(expectLater(load1Future, completion(audioSourceDuration)));
    await stop1Future.catchError((e) => null);
    await load1Future.catchError((e) => null);
    await player.dispose();
  });

  test('load-simultaneous', () async {
    final player = AudioPlayer();
    // Activate the platform
    await player.setAudioSource(AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')));
    // Do two simultaneous loads
    mock.mostRecentPlayer?.blockLoad();
    final load1Future = player.setAudioSource(AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')));
    // Wait for first load to enter platform before starting second load.
    await player.processingStateStream.firstWhere((s) => s == ProcessingState.loading);
    final load2Future = player.setAudioSource(AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')));
    mock.mostRecentPlayer?.unblockLoad();
    unawaited(expectLater(() => load1Future, throwsException));
    unawaited(expectLater(load2Future, completion(audioSourceDuration)));
    await load1Future.catchError((e) => null);
    await load2Future.catchError((e) => null);
    await player.dispose();
  });

  test('load-load', () async {
    final player = AudioPlayer();
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
    ]);
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.sequence.length, equals(2));
    expect(player.playing, equals(false));
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/baz.mp3')),
    ]);
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.sequence.length, equals(3));
    expect(player.playing, equals(false));
    await player.dispose();
  });

  test('load-set-load', () async {
    final player = AudioPlayer();
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
    ]);
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.sequence.length, equals(2));
    expect(player.playing, equals(false));
    await player.setAudioSources([
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/baz.mp3')),
    ], preload: false);
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.sequence.length, equals(3));
    expect(player.playing, equals(false));
    await player.load();
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.sequence.length, equals(3));
    expect(player.playing, equals(false));
    await player.dispose();
  });

  test('play-load-load', () async {
    final player = AudioPlayer();
    unawaited(player.play());
    await player.setUrl('https://bar.bar/foo.mp3');
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.playing, equals(true));
    expectDuration(player.position, Duration.zero);
    const playDuration = Duration(milliseconds: 50);
    await Future<dynamic>.delayed(playDuration);
    expectDuration(player.position, playDuration);
    await player.setUrl('https://bar.bar/bar.mp3');
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.playing, equals(true));
    final startPosition = player.position;
    expectDuration(startPosition, Duration.zero, epsilon: 100);
    await Future<dynamic>.delayed(playDuration);
    expectDuration(player.position, startPosition + playDuration);
    await player.dispose();
  });

  test('play-load-set-play-load', () async {
    final player = AudioPlayer();
    unawaited(player.play());
    await player.setUrl('https://bar.bar/foo.mp3');
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.playing, equals(true));
    expectDuration(player.position, Duration.zero);
    const playDuration = Duration(milliseconds: 50);
    await Future<dynamic>.delayed(playDuration);
    expectDuration(player.position, playDuration);
    unawaited(player.pause());
    expect(player.playing, equals(false));
    await player.setUrl('https://bar.bar/bar.mp3', preload: false);
    expect(player.processingState, equals(ProcessingState.idle));
    expect(player.playing, equals(false));
    expectDuration(player.position, Duration.zero);
    await player.load();
    expect(player.processingState, equals(ProcessingState.ready));
    expect(player.playing, equals(false));
    expectDuration(player.position, Duration.zero);
    unawaited(player.play());
    expect(player.playing, equals(true));
    expectDuration(player.position, Duration.zero);
    await Future<dynamic>.delayed(playDuration);
    expectDuration(player.position, playDuration);
    await player.dispose();
  });

  test('quick-reactivate', () async {
    final player = AudioPlayer();
    await player.setUrl('https://bar.bar/foo.mp3');
    unawaited(player.stop());
    await player.setUrl('https://bar.bar/foo.mp3');
    await player.dispose();
  });

  test('play-pause', () async {
    final player = AudioPlayer();
    await player.setUrl('https://bar.bar/foo.mp3');
    unawaited(player.play());
    await player.pause();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(mock.mostRecentPlayer?._playing, false);
    await player.dispose();
  });

  test('play-stop', () async {
    final player = AudioPlayer();
    await player.setUrl('https://bar.bar/foo.mp3');
    unawaited(player.play());
    await player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(mock.mostRecentPlayer?._playing, false);
    await player.dispose();
  });

  test('positionStream emissions: seek while paused', () async {
    final player = AudioPlayer();
    await player.setUrl('https://bar.bar/foo.mp3');
    expectState(player: player, position: Duration.zero, processingState: ProcessingState.ready, playing: false);
    var completer = Completer<dynamic>();
    late StreamSubscription<Duration> subscription;
    subscription = player.positionStream.listen((position) {
      expectDuration(position, Duration.zero);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    const duration1 = Duration(seconds: 1);
    const duration2 = Duration(milliseconds: 100);
    const duration3 = Duration(milliseconds: 80);

    await player.seek(duration1);
    expectState(player: player, position: duration1, processingState: ProcessingState.ready, playing: false);
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      expectDuration(position, duration1);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    unawaited(player.play());
    await Future<dynamic>.delayed(duration2);
    expectState(player: player, position: duration1 + duration2, processingState: ProcessingState.ready, playing: true);
    await player.pause();
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      expectDuration(position, duration1 + duration2);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    await player.seek(duration1 + duration2 + duration3);
    expectState(
      player: player,
      position: duration1 + duration2 + duration3,
      processingState: ProcessingState.ready,
      playing: false,
    );
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      expectDuration(position, duration1 + duration2 + duration3);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    await player.dispose();
  });

  test('positionStream emissions: switch audio sources', () async {
    final player = AudioPlayer();
    final playlist = [
      AudioSource.uri(Uri.parse('https://bar.bar/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
    ];
    await player.setAudioSources(playlist);
    expectState(player: player, position: Duration.zero, processingState: ProcessingState.ready, playing: false);
    expect(player.currentIndex, 0);
    var completer = Completer<dynamic>();
    late StreamSubscription<Duration> subscription;
    subscription = player.positionStream.listen((position) {
      expectDuration(position, Duration.zero);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    const duration1 = Duration(seconds: 1);
    const duration2 = Duration(seconds: 600);

    await player.seek(duration1);
    expect(player.currentIndex, 0);
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      expectDuration(position, duration1);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    await player.seekToNext();
    expect(player.currentIndex, 1);
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      expectDuration(position, Duration.zero);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    await player.seek(duration1, index: 1);
    expect(player.currentIndex, 1);
    await player.seekToNext();
    // There is no next
    expect(player.currentIndex, 1);
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      // No position change because there is no next
      expectDuration(position, duration1);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    // Switch to index 0 and seek position at the same time
    await player.seek(duration2, index: 0);
    expect(player.currentIndex, 0);
    completer = Completer<dynamic>();
    subscription = player.positionStream.listen((position) {
      expectDuration(position, duration2);
      unawaited(subscription.cancel());
      completer.complete();
    });
    await completer.future;

    await player.dispose();
  });

  test('positionDiscontinuity', () async {
    final player = AudioPlayer();
    final discontinuityEvents = <PositionDiscontinuity>[];
    final subscription = player.positionDiscontinuityStream.listen(discontinuityEvents.add);
    final playlist = [
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3'), tag: 'a'),
      AudioSource.uri(Uri.parse('https://baz.baz/baz.mp3'), tag: 'b'),
    ];
    await player.setAudioSources(playlist);
    expect(player.currentIndex, equals(0));
    expect(discontinuityEvents.length, equals(0));
    unawaited(player.play());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(discontinuityEvents.length, equals(0));
    for (final mockPlayer in mock._players.values) {
      await mockPlayer._autoAdvance();
    }
    expect(player.currentIndex, equals(1));
    expect(
      discontinuityEvents.length == 1 && discontinuityEvents.first.reason == PositionDiscontinuityReason.autoAdvance,
      equals(true),
    );
    discontinuityEvents.clear();
    await player.seek(Duration.zero, index: 0);
    expect(player.currentIndex, equals(0));
    expect(
      discontinuityEvents.length == 1 && discontinuityEvents.first.reason == PositionDiscontinuityReason.seek,
      equals(true),
    );
    discontinuityEvents.clear();
    // Test loop one
    await player.setLoopMode(LoopMode.one);
    await player.seek(const Duration(seconds: 119));
    discontinuityEvents.clear();
    for (final mockPlayer in mock._players.values) {
      await mockPlayer._autoAdvance();
    }
    expect(player.currentIndex, equals(0));
    expect(
      discontinuityEvents.length == 1 && discontinuityEvents.first.reason == PositionDiscontinuityReason.autoAdvance,
      equals(true),
    );
    discontinuityEvents.clear();

    await player.dispose();
    unawaited(subscription.cancel());
  });

  test('loadConfiguration', () async {
    const audioLoadConfiguration = AudioLoadConfiguration(
      darwinLoadControl: DarwinLoadControl(),
      androidLoadControl: AndroidLoadControl(),
      androidLivePlaybackSpeedControl: AndroidLivePlaybackSpeedControl(),
    );
    final player = AudioPlayer(audioLoadConfiguration: audioLoadConfiguration);
    await player.setUrl('https://foo.foo/foo.mp3');
    final platformPlayer = mock.mostRecentPlayer!;
    expect(
      platformPlayer.audioLoadConfiguration?.darwinLoadControl?.automaticallyWaitsToMinimizeStalling,
      equals(audioLoadConfiguration.darwinLoadControl?.automaticallyWaitsToMinimizeStalling),
    );
    // TODO(SunnatilloShavkatov): check other fields.
    await player.dispose();
  });

  test('AndroidLoudnessEnhancer', () async {
    final loudnessEnhancer = AndroidLoudnessEnhancer();
    final player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [loudnessEnhancer]));
    expect(loudnessEnhancer.targetGain, equals(0.0));
    expect(await loudnessEnhancer.targetGainStream.first, equals(0.0));
    await player.setUrl('https://foo.foo/foo.mp3');
    expect(loudnessEnhancer.targetGain, equals(0.0));
    expect(await loudnessEnhancer.targetGainStream.first, equals(0.0));
    await loudnessEnhancer.setTargetGain(1.5);
    expect(loudnessEnhancer.targetGain, equals(1.5));
    expect(await loudnessEnhancer.targetGainStream.first, equals(1.5));
    expect(loudnessEnhancer.enabled, equals(false));
    expect(await loudnessEnhancer.enabledStream.first, equals(false));
    await loudnessEnhancer.setEnabled(enabled: true);
    expect(loudnessEnhancer.enabled, equals(true));
    expect(await loudnessEnhancer.enabledStream.first, equals(true));
  });

  test('AndroidEqualizer', () async {
    final equalizer = AndroidEqualizer();
    final player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]));
    expect(equalizer.enabled, equals(false));
    expect(await equalizer.enabledStream.first, equals(false));
    await player.setUrl('https://foo.foo/foo.mp3');
    expect(equalizer.enabled, equals(false));
    expect(await equalizer.enabledStream.first, equals(false));
    await equalizer.setEnabled(enabled: true);
    expect(equalizer.enabled, equals(true));
    expect(await equalizer.enabledStream.first, equals(true));
    final parameters = await equalizer.parameters;
    expect(parameters.minDecibels, equals(0.0));
    expect(parameters.maxDecibels, equals(10.0));
    final bands = parameters.bands;
    expect(bands.length, equals(5));
    for (var i = 0; i < 5; i++) {
      final band = bands[i];
      expect(band.index, equals(i));
      expect(band.lowerFrequency, equals(i * 1000));
      expect(band.upperFrequency, equals((i + 1) * 1000));
      expect(band.centerFrequency, equals((i + 0.5) * 1000));
      expect(band.gain, equals(i * 0.1));
      expect(await band.gainStream.first, equals(i * 0.1));
      final newGain = i * 0.2;
      await band.setGain(newGain);
      expect(band.gain, equals(newGain));
    }
    await player.stop();
    await player.load();
    expect(equalizer.enabled, equals(true));
    expect(parameters.minDecibels, equals(0.0));
    expect(parameters.maxDecibels, equals(10.0));
    expect(bands.length, equals(5));
    for (var i = 0; i < 5; i++) {
      final band = bands[i];
      expect(band.index, equals(i));
      expect(band.lowerFrequency, equals(i * 1000));
      expect(band.upperFrequency, equals((i + 1) * 1000));
      expect(band.centerFrequency, equals((i + 0.5) * 1000));
      expect(band.gain, equals(i * 0.2));
    }
  });

  test('Android audio effects are inert on iOS', () async {
    AudioPlayerTestHooks.testTargetPlatform = TargetPlatform.iOS;
    addTearDown(() => AudioPlayerTestHooks.testTargetPlatform = TargetPlatform.android);
    final equalizer = AndroidEqualizer();
    final loudnessEnhancer = AndroidLoudnessEnhancer();
    final player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, loudnessEnhancer]));
    expect(await player.setUrl('https://foo.foo/foo.mp3'), equals(audioSourceDuration));
    await equalizer.setEnabled(enabled: true);
    await loudnessEnhancer.setTargetGain(1.5);
    expect(equalizer.enabled, isTrue);
    expect(loudnessEnhancer.targetGain, equals(1.5));
    final platform = mock.mostRecentPlayer!;
    expect(platform.initRequest.androidAudioEffects, isEmpty);
    expect(platform.audioEffectCalls, isEmpty);
    await player.setAndroidAudioAttributes(const AndroidAudioAttributes(usage: AndroidAudioUsage.alarm));
    expect(platform.audioEffectCalls, isEmpty);
    await player.dispose();
  });

  test('asyncMessages', () async {
    final player = AudioPlayer();
    await player.setUrl('https://foo.foo/foo.mp3');
    final platform = mock.mostRecentPlayer!;
    expect(player.playing, equals(false));
    expect(player.volume, equals(1.0));
    expect(player.speed, equals(1.0));
    expect(player.pitch, equals(1.0));
    expect(player.loopMode, LoopMode.off);
    expect(player.shuffleModeEnabled, equals(false));
    platform._broadcastDataMessage(
      PlayerDataMessage(
        playing: true,
        volume: 0.7,
        speed: 0.8,
        pitch: 0.9,
        loopMode: LoopModeMessage.all,
        shuffleMode: ShuffleModeMessage.all,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, equals(true));
    expect(player.volume, equals(0.7));
    expect(player.speed, equals(0.8));
    expect(player.pitch, equals(0.9));
    expect(player.loopMode, equals(LoopMode.all));
    expect(player.shuffleModeEnabled, equals(true));
    await player.dispose();
  });

  group('setting rollback lifecycle', () {
    for (final setting in ['volume', 'speed', 'pitch', 'skipSilence']) {
      for (final disposeBeforeFailure in [false, true]) {
        test('$setting preserves platform error after failure, disposed=$disposeBeforeFailure', () async {
          final requestReached = Completer<void>();
          final response = Completer<void>();
          var armed = false;
          Future<void> handleRequest() async {
            if (!armed) {
              return;
            }
            requestReached.complete();
            await response.future;
          }

          mock
            ..onSetVolume = setting == 'volume' ? handleRequest : null
            ..onSetSpeed = setting == 'speed' ? handleRequest : null
            ..onSetPitch = setting == 'pitch' ? handleRequest : null
            ..onSetSkipSilence = setting == 'skipSilence' ? handleRequest : null;
          addTearDown(() {
            mock
              ..onSetVolume = null
              ..onSetSpeed = null
              ..onSetPitch = null
              ..onSetSkipSilence = null;
          });
          final player = AudioPlayer();
          addTearDown(player.dispose);
          await player.setUrl('https://foo.foo/foo.mp3');
          armed = true;
          final error = PlatformException(code: 'error', message: '$setting failed');
          final request = switch (setting) {
            'volume' => player.setVolume(0.5),
            'speed' => player.setSpeed(1.5),
            'pitch' => player.setPitch(1.5),
            _ => player.setSkipSilenceEnabled(enabled: true),
          };
          final expectation = expectLater(request, throwsA(same(error)));
          await requestReached.future;
          if (disposeBeforeFailure) {
            await player.dispose();
          }
          response.completeError(error);
          await expectation;
          if (!disposeBeforeFailure) {
            expect(switch (setting) {
              'volume' => player.volume,
              'speed' => player.speed,
              'pitch' => player.pitch,
              _ => player.skipSilenceEnabled,
            }, equals(setting == 'skipSilence' ? false : 1.0));
          }
        });
      }
    }
  });

  group('pause lifecycle', () {
    for (final dispose in [false, true]) {
      test('pause does not use a retired platform, dispose=$dispose', () async {
        mock.onInit = (platform) => platform.blockLoad();
        addTearDown(() => mock.onInit = null);
        final player = AudioPlayer();
        addTearDown(player.dispose);
        final load = player.setUrl('https://foo.foo/foo.mp3');
        final loadExpectation = expectLater(load, throwsA(isA<PlayerInterruptedException>()));
        await player.processingStateStream.firstWhere((state) => state == ProcessingState.loading);
        await Future<void>.delayed(Duration.zero);
        final native = mock.mostRecentPlayer!;
        final play = player.play();
        final pause = player.pause();
        final pauseExpectation = expectLater(pause, completes);
        await Future<void>.delayed(Duration.zero);
        if (dispose) {
          await player.dispose();
        } else {
          await player.stop();
        }
        native.unblockLoad();
        await loadExpectation;
        await pauseExpectation;
        await play;
        expect(player.playing, isFalse);
      });
    }

    test('pause still reports errors from the current platform', () async {
      final player = AudioPlayer();
      addTearDown(player.dispose);
      await player.setUrl('https://foo.foo/foo.mp3');
      final native = mock.mostRecentPlayer!;
      final error = PlatformException(code: 'pause-failed');
      native.pauseError = error;
      final play = player.play();
      await expectLater(player.pause(), throwsA(same(error)));
      await play;
    });
  });

  group('native error details', () {
    test('a string details value still becomes a PlayerException', () async {
      mock.onInit = (platform) => platform.loadError = PlatformException(
        code: 'error',
        message: 'Error in load',
        details: 'IllegalStateException: boom',
      );
      addTearDown(() => mock.onInit = null);
      final player = AudioPlayer();
      addTearDown(player.dispose);
      await expectLater(
        player.setUrl('https://foo.foo/foo.mp3'),
        throwsA(isA<PlayerException>().having((e) => e.message, 'message', 'Error in load')),
      );
    });
  });

  group('seek before the first play', () {
    final sources = [
      AudioSource.uri(Uri.parse('https://foo.foo/foo.mp3')),
      AudioSource.uri(Uri.parse('https://bar.bar/bar.mp3')),
      AudioSource.uri(Uri.parse('https://baz.baz/baz.mp3')),
    ];

    test('starts the native player at the sought index and position', () async {
      final player = AudioPlayer();
      addTearDown(player.dispose);
      await player.setAudioSources(sources, preload: false);
      await player.seek(const Duration(seconds: 30), index: 2);
      final play = player.play();
      await player.processingStateStream.firstWhere((state) => state == ProcessingState.ready);
      final request = mock.mostRecentPlayer!.lastLoadRequest!;
      expect(request.initialIndex, 2);
      expect(request.initialPosition, const Duration(seconds: 30));
      await player.pause();
      await play;
    });

    test('keeps the initial index when a seek is dropped while loading', () async {
      final gate = Completer<void>();
      mock.onSetVolume = () => gate.future;
      addTearDown(() => mock.onSetVolume = null);
      final player = AudioPlayer();
      addTearDown(player.dispose);
      await player.setVolume(0.5);
      final load = player.setAudioSources(sources, initialIndex: 2);
      final loadExpectation = expectLater(load, completes);
      await player.processingStateStream.firstWhere((state) => state == ProcessingState.loading);
      await player.seek(const Duration(seconds: 5));
      gate.complete();
      await loadExpectation;
      expect(mock.mostRecentPlayer!.lastLoadRequest!.initialIndex, 2);
    });
  });

  group('interrupted startup', () {
    test('a second setUrl while the first starts leaves the player usable', () async {
      final gate = mock.initGate = Completer<void>();
      addTearDown(() => mock.initGate = null);
      final player = AudioPlayer();
      addTearDown(player.dispose);
      final first = player.setUrl('https://foo.foo/first.mp3');
      final firstExpectation = expectLater(first, throwsA(isA<PlayerInterruptedException>()));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = player.setUrl('https://foo.foo/second.mp3');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      gate.complete();
      await firstExpectation;
      await second;
      await player.setVolume(0.5);
      await player.seek(const Duration(seconds: 1));
      final play = player.play();
      await player.pause();
      await play;
      expect(player.volume, 0.5);
    });
  });

  group('playlist edits during startup', () {
    List<AudioSource> sources(int count) => [
      for (var i = 0; i < count; i++) AudioSource.uri(Uri.parse('https://foo.foo/$i.mp3'), tag: '$i'),
    ];

    Future<AudioPlayer> startWithGate(int count, Completer<void> gate) async {
      mock.initGate = gate;
      addTearDown(() => mock.initGate = null);
      final player = AudioPlayer();
      addTearDown(player.dispose);
      await player.setAudioSources(sources(count), preload: false);
      unawaited(player.play());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return player;
    }

    int loadedChildren() =>
        (mock.mostRecentPlayer!.lastLoadRequest!.audioSourceMessage as ConcatenatingAudioSourceMessage).children.length;

    test('an added source is not sent again after the load that includes it', () async {
      final gate = Completer<void>();
      final player = await startWithGate(1, gate);
      final add = player.addAudioSource(AudioSource.uri(Uri.parse('https://foo.foo/added.mp3'), tag: 'added'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      gate.complete();
      await add;
      await player.processingStateStream.firstWhere((state) => state == ProcessingState.ready);
      expect(loadedChildren(), 2);
      expect(mock.mostRecentPlayer!.insertAllRequests, isEmpty);
      expect(player.sequence, hasLength(2));
    });

    test('a removed source is not removed again after the load that excludes it', () async {
      final gate = Completer<void>();
      final player = await startWithGate(3, gate);
      final remove = player.removeAudioSourceAt(1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      gate.complete();
      await remove;
      await player.processingStateStream.firstWhere((state) => state == ProcessingState.ready);
      expect(loadedChildren(), 2);
      expect(mock.mostRecentPlayer!.removeRangeRequests, isEmpty);
    });

    test('an edit after the load was sent still reaches the platform', () async {
      final player = AudioPlayer();
      addTearDown(player.dispose);
      await player.setAudioSources(sources(1));
      await player.addAudioSource(AudioSource.uri(Uri.parse('https://foo.foo/added.mp3')));
      expect(mock.mostRecentPlayer!.insertAllRequests, hasLength(1));
    });
  });

  group('activation failure', () {
    tearDown(() {
      mock
        ..initError = null
        ..onSetVolume = null;
    });

    test('play() fails, reports the error and leaves the player usable', () async {
      mock.onSetVolume = () async => throw PlatformException(code: 'error', message: 'setVolume failed');
      final player = AudioPlayer();
      final errors = <PlayerException>[];
      final subscription = player.errorStream.listen(errors.add);
      // The idle platform accepts the volume; the native one rejects it.
      await player.setVolume(0.5);
      await player.setUrl('https://foo.foo/foo.mp3', preload: false);
      await expectLater(
        player.play().timeout(const Duration(seconds: 1)),
        throwsA(isA<PlayerException>().having((e) => e.message, 'message', 'setVolume failed')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
      expect(player.processingState, equals(ProcessingState.idle));
      expect(errors.single.message, equals('setVolume failed'));

      // No stale error is left behind, and the next activation works.
      mock.onSetVolume = null;
      await player.pause();
      await player.seek(Duration.zero);
      expect(await player.load(), equals(audioSourceDuration));
      final playFuture = player.play();
      await player.pause();
      await playFuture.timeout(const Duration(seconds: 1));
      await subscription.cancel();
      await player.dispose();
    });

    test('load() fails when the platform player cannot be created', () async {
      mock.initError = PlatformException(code: 'error', message: 'init failed');
      final player = AudioPlayer();
      await expectLater(
        player.setUrl('https://foo.foo/foo.mp3'),
        throwsA(isA<PlayerException>().having((e) => e.message, 'message', 'init failed')),
      );
      expect(player.processingState, equals(ProcessingState.idle));
      expect(await player.setUrl('https://foo.foo/foo.mp3'), equals(audioSourceDuration));
      await player.dispose();
    });

    test('play() completes on pause when its activation is superseded', () async {
      final setVolumeReached = Completer<void>();
      final releaseSetVolume = Completer<void>();
      mock.onSetVolume = () {
        if (!setVolumeReached.isCompleted) {
          setVolumeReached.complete();
        }
        return releaseSetVolume.future;
      };
      final player = AudioPlayer();
      await player.setVolume(0.5);
      await player.setUrl('https://foo.foo/foo.mp3', preload: false);
      final playFuture = player.play();
      await setVolumeReached.future;
      // Stopping supersedes the activation before it sends the play request.
      await player.stop();
      releaseSetVolume.complete();
      await playFuture.timeout(const Duration(seconds: 1));
      expect(player.playing, isFalse);
      await player.dispose();
    });
  });
}

class MockAudioPlayerPlatform extends Mock with MockPlatformInterfaceMixin implements AudioPlayerPlatform {
  MockAudioPlayer? mostRecentPlayer;
  final _players = <String, MockAudioPlayer>{};
  void Function(MockAudioPlayer)? onInit;

  /// When set, the next [init] call fails with this error.
  Exception? initError;

  /// When set, [init] waits for this to complete before creating the player.
  Completer<void>? initGate;

  /// Called by [MockAudioPlayer.setVolume] of the players created from now on.
  Future<void> Function()? onSetVolume;

  /// Called by [MockAudioPlayer.setSpeed] of newly created players.
  Future<void> Function()? onSetSpeed;

  /// Called by [MockAudioPlayer.setPitch] of newly created players.
  Future<void> Function()? onSetPitch;

  /// Called by [MockAudioPlayer.setSkipSilence] of newly created players.
  Future<void> Function()? onSetSkipSilence;

  @override
  Future<AudioPlayerInstancePlatform> init(InitRequest request) async {
    await initGate?.future;
    final error = initError;
    if (error != null) {
      initError = null;
      throw error;
    }
    if (_players.containsKey(request.id)) {
      throw PlatformException(code: 'error', message: 'Platform player ${request.id} already exists');
    }
    final player = MockAudioPlayer(
      request,
      onSetVolume: onSetVolume,
      onSetSpeed: onSetSpeed,
      onSetPitch: onSetPitch,
      onSetSkipSilence: onSetSkipSilence,
    );
    onInit?.call(player);
    _players[request.id] = player;
    mostRecentPlayer = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    unawaited(_players[request.id]!.dispose(DisposeRequest()));
    _players.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    for (final player in _players.values) {
      unawaited(player.dispose(DisposeRequest()));
    }
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

const audioSourceDuration = Duration(seconds: 30);

const icyMetadata = IcyMetadata(
  headers: IcyHeaders(url: 'url', genre: 'Genre', metadataInterval: 3, bitrate: 100, isPublic: true, name: 'name'),
  info: IcyInfo(title: 'title', url: 'url'),
);

final icyMetadataMessage = IcyMetadataMessage(
  headers: IcyHeadersMessage(
    url: 'url',
    genre: 'Genre',
    metadataInterval: 3,
    bitrate: 100,
    isPublic: true,
    name: 'name',
  ),
  info: IcyInfoMessage(title: 'title', url: 'url'),
);

class MockAudioPlayer extends AudioPlayerInstancePlatform {
  new(this.initRequest, {this.onSetVolume, this.onSetSpeed, this.onSetPitch, this.onSetSkipSilence})
    : audioLoadConfiguration = initRequest.audioLoadConfiguration,
      super(initRequest.id);
  final InitRequest initRequest;
  final Future<void> Function()? onSetVolume;
  final Future<void> Function()? onSetSpeed;
  final Future<void> Function()? onSetPitch;
  final Future<void> Function()? onSetSkipSilence;

  /// The most recent [load] request.
  LoadRequest? lastLoadRequest;

  /// The playlist edits received so far.
  final insertAllRequests = <ConcatenatingInsertAllRequest>[];
  final removeRangeRequests = <ConcatenatingRemoveRangeRequest>[];

  /// When set, [load] fails with this error.
  Exception? loadError;

  /// The names of the audio effect and Android-only methods called so far.
  final audioEffectCalls = <String>[];
  final eventController = StreamController<PlaybackEventMessage>();
  final dataMessageController = StreamController<PlayerDataMessage>();
  final AudioLoadConfigurationMessage? audioLoadConfiguration;
  AudioSourceMessage? _audioSource;
  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _updatePosition = Duration.zero;
  DateTime _updateTime = DateTime.now();
  MockLoadRequest? _loadRequest;
  Duration? _duration;
  int? _index;
  var _playing = false;
  var _speed = 1.0;
  Completer<dynamic>? _playCompleter;
  Timer? _playTimer;
  LoopModeMessage _loopMode = LoopModeMessage.off;
  int? _errorCode;
  String? _errorMessage;
  Completer<void>? _loadBlock;
  bool _disposed = false;
  Exception? pauseError;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => dataMessageController.stream;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => eventController.stream;

  void _broadcastDataMessage(PlayerDataMessage message) {
    dataMessageController.add(message);
  }

  void blockLoad() {
    _loadBlock ??= Completer();
  }

  void unblockLoad() {
    _loadBlock?.complete();
    _loadBlock = null;
  }

  Future<void> _loadReady() async {
    if (_loadBlock != null) {
      await _loadBlock!.future;
    }
  }

  PlatformException _sendError(int errorCode, String errorMessage, {bool switchToIdle = true}) {
    final e = PlatformException(code: '$errorCode', message: errorMessage);
    eventController.addError(e);
    if (switchToIdle) {
      _processingState = ProcessingStateMessage.idle;
    }
    _errorCode = errorCode;
    _errorMessage = errorMessage;
    _broadcastPlaybackEvent();
    return e;
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    lastLoadRequest = request;
    if (loadError case final error?) {
      throw error;
    }
    _loadRequest?.interrupted = true;
    final loadRequest = _loadRequest = MockLoadRequest();
    final playlist = request.audioSourceMessage as ConcatenatingAudioSourceMessage;
    if (playlist.children.isEmpty) {
      return LoadResponse(duration: null);
    }
    final audioSource = playlist.children.first;
    _processingState = ProcessingStateMessage.loading;
    _errorCode = null;
    _errorMessage = null;
    _broadcastPlaybackEvent();
    if (audioSource is UriAudioSourceMessage) {
      final uri = Uri.parse(audioSource.uri);
      if (uri.path.contains('abort')) {
        throw _sendError(415, 'Failed to load URL');
      } else if (uri.path.contains('404')) {
        throw _sendError(404, 'Not found: ${audioSource.uri}');
      } else if (uri.path.contains('error')) {
        throw _sendError(500, 'Unknown error');
      }
      _duration = audioSourceDuration;
    } else if (audioSource is ClippingAudioSourceMessage) {
      _duration = (audioSource.end ?? audioSourceDuration) - (audioSource.start ?? Duration.zero);
    } else {
      // TODO(SunnatilloShavkatov): pull the sequence out of the audio source and return the duration
      // of the first item in the sequence.
      _duration = audioSourceDuration;
    }
    _audioSource = audioSource;
    _index = request.initialIndex ?? 0;
    // Simulate loading time.
    await _loadReady();
    if (loadRequest.interrupted) {
      throw _sendError(10000000, 'Connection aborted', switchToIdle: false);
    }
    _setPosition(request.initialPosition ?? Duration.zero);
    _processingState = ProcessingStateMessage.ready;
    _broadcastPlaybackEvent();
    if (_playing) {
      _startTimer();
    }
    _loadRequest = null;
    return LoadResponse(duration: _duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    if (_playing) {
      return PlayResponse();
    }
    _playing = true;
    if (_duration != null) {
      _startTimer();
    }
    _playCompleter = Completer<dynamic>();
    await _playCompleter!.future;
    return PlayResponse();
  }

  void _startTimer() {
    _playTimer = Timer(_remaining, () {
      _setPosition(_position);
      _processingState = ProcessingStateMessage.completed;
      _errorCode = null;
      _errorMessage = null;
      _broadcastPlaybackEvent();
      _playCompleter?.complete();
    });
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    if (_disposed) {
      throw MissingPluginException('No implementation found for method pause on disposed player $id');
    }
    if (pauseError case final error?) {
      throw error;
    }
    if (!_playing) {
      return PauseResponse();
    }
    _setPosition(_position);
    _playing = false;
    _playTimer?.cancel();
    _playCompleter?.complete();
    _broadcastPlaybackEvent();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _setPosition(request.position ?? Duration.zero);
    _index = request.index ?? 0;
    _broadcastPlaybackEvent();
    return SeekResponse();
  }

  Future<void> _autoAdvance() async {
    _setPosition(Duration.zero);
    if (_loopMode == LoopModeMessage.off) {
      _index = _index! + 1;
    }
    _broadcastPlaybackEvent();
  }

  final androidAudioAttributesRequests = <SetAndroidAudioAttributesRequest>[];

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) async {
    audioEffectCalls.add('setAndroidAudioAttributes');
    androidAudioAttributesRequests.add(request);
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    _loopMode = request.loopMode;
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async => SetShuffleOrderResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    await onSetSpeed?.call();
    _speed = request.speed;
    _setPosition(_position);
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    await onSetPitch?.call();
    return SetPitchResponse();
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async {
    await onSetSkipSilence?.call();
    return SetSkipSilenceResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    await onSetVolume?.call();
    return SetVolumeResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _disposed = true;
    await Future<dynamic>.delayed(const Duration(milliseconds: 10));
    _processingState = ProcessingStateMessage.idle;
    _errorCode = null;
    _errorMessage = null;
    _broadcastPlaybackEvent();
    unawaited(eventController.close());
    return DisposeResponse();
  }

  // TODO(SunnatilloShavkatov): Update the mock playlist for this request.
  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(ConcatenatingInsertAllRequest request) async {
    insertAllRequests.add(request);
    return ConcatenatingInsertAllResponse();
  }

  // TODO(SunnatilloShavkatov): Update the mock playlist for this request.
  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(ConcatenatingMoveRequest request) async =>
      ConcatenatingMoveResponse();

  // TODO(SunnatilloShavkatov): Update the mock playlist for this request.
  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(ConcatenatingRemoveRangeRequest request) async {
    removeRangeRequests.add(request);
    return ConcatenatingRemoveRangeResponse();
  }

  void _broadcastPlaybackEvent() {
    String? url;
    if (_audioSource is UriAudioSourceMessage) {
      // Not sure why this cast is necessary...
      url = (_audioSource! as UriAudioSourceMessage).uri;
    }
    eventController.add(
      PlaybackEventMessage(
        processingState: _processingState,
        errorCode: _errorCode,
        errorMessage: _errorMessage,
        updatePosition: _updatePosition,
        updateTime: _updateTime,
        bufferedPosition: _position,
        icyMetadata: IcyMetadataMessage(
          headers: IcyHeadersMessage(
            url: url,
            genre: 'Genre',
            metadataInterval: 3,
            bitrate: 100,
            isPublic: true,
            name: 'name',
          ),
          info: IcyInfoMessage(title: 'title', url: url),
        ),
        duration: _duration,
        currentIndex: _index,
        androidAudioSessionId: null,
      ),
    );
  }

  Duration get _position {
    if (_playing && _processingState == ProcessingStateMessage.ready) {
      final result = _updatePosition + (DateTime.now().difference(_updateTime)) * _speed;
      return result <= _duration! ? result : _duration!;
    } else {
      return _updatePosition;
    }
  }

  Duration get _remaining => (_duration! - _position) * (1 / _speed);

  void _setPosition(Duration position) {
    _updatePosition = position;
    _updateTime = DateTime.now();
  }

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) async => SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) async {
    audioEffectCalls.add('audioEffectSetEnabled');
    return AudioEffectSetEnabledResponse();
  }

  @override
  Future<AndroidLoudnessEnhancerSetTargetGainResponse> androidLoudnessEnhancerSetTargetGain(
    AndroidLoudnessEnhancerSetTargetGainRequest request,
  ) async {
    audioEffectCalls.add('androidLoudnessEnhancerSetTargetGain');
    return AndroidLoudnessEnhancerSetTargetGainResponse();
  }

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
    AndroidEqualizerGetParametersRequest request,
  ) async {
    audioEffectCalls.add('androidEqualizerGetParameters');
    return androidEqualizerParameters;
  }

  static final androidEqualizerParameters = AndroidEqualizerGetParametersResponse(
    parameters: AndroidEqualizerParametersMessage(
      minDecibels: 0,
      maxDecibels: 10,
      bands: [
        for (var i = 0; i < 5; i++)
          AndroidEqualizerBandMessage(
            index: i,
            lowerFrequency: i * 1000,
            upperFrequency: (i + 1) * 1000,
            centerFrequency: (i + 0.5) * 1000,
            gain: i * 0.1,
          ),
      ],
    ),
  );

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
    AndroidEqualizerBandSetGainRequest request,
  ) async => AndroidEqualizerBandSetGainResponse();
}

class MockLoadRequest {
  bool interrupted = false;
}
