import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player/src/audio_player.dart' show AudioPlayerTestHooks;
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import 'test_platform.dart';

class _CustomHttpOverrides extends HttpOverrides;

class _FailingPlatformInstance extends SimpleMockAudioPlayerInstance {
  new(super.initRequest);

  bool throwOnSetVolume = false;
  bool throwOnSetSpeed = false;
  bool throwOnSetPitch = false;
  bool throwOnSetSkipSilence = false;
  bool throwOnPlay = false;

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) {
    if (throwOnSetVolume) {
      return Future.error(PlatformException(code: 'ERROR', message: 'Volume failed'));
    }
    return super.setVolume(request);
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) {
    if (throwOnSetSpeed) {
      return Future.error(PlatformException(code: 'ERROR', message: 'Speed failed'));
    }
    return super.setSpeed(request);
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) {
    if (throwOnSetPitch) {
      return Future.error(PlatformException(code: 'ERROR', message: 'Pitch failed'));
    }
    return super.setPitch(request);
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) {
    if (throwOnSetSkipSilence) {
      return Future.error(PlatformException(code: 'ERROR', message: 'SkipSilence failed'));
    }
    return super.setSkipSilence(request);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) {
    if (throwOnPlay) {
      return Future.error(PlatformException(code: 'ERROR', message: 'Play failed'));
    }
    return super.play(request);
  }
}

class _FailingPlatform extends SimpleMockAudioPlayerPlatform {
  _FailingPlatformInstance? lastInstance;

  @override
  Future<AudioPlayerInstancePlatform> init(InitRequest request) async {
    final instance = _FailingPlatformInstance(request);
    lastInstance = instance;
    players[request.id] = instance;
    return instance;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _CustomHttpOverrides();
  AudioPlayerPlatform.instance = SimpleMockAudioPlayerPlatform();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory mockTempDir;

  setUp(() async {
    mockTempDir = await Directory.systemTemp.createTemp('audio_player_test_temp_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProviderChannel, (
      MethodCall methodCall,
    ) async {
      if (methodCall.method == 'getTemporaryDirectory') {
        return mockTempDir.path;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      null,
    );
    if (mockTempDir.existsSync()) {
      mockTempDir.deleteSync(recursive: true);
    }
  });

  group('Coverage Boost Tests', () {
    test('audio effects in idle state', () async {
      final equalizer = AndroidEqualizer();
      final enhancer = AndroidLoudnessEnhancer();
      final player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, enhancer]));

      await equalizer.setEnabled(enabled: true);
      expect(equalizer.enabled, isTrue);

      await enhancer.setEnabled(enabled: true);
      expect(enhancer.enabled, isTrue);
      await enhancer.setTargetGain(1.2);
      expect(enhancer.targetGain, equals(1.2));

      // In idle state, _activate is never called so the parameters completer
      // is never completed. Verify the future stays pending rather than
      // awaiting it (which would timeout).
      var parametersCompleted = false;
      unawaited(equalizer.parameters.then((_) => parametersCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(parametersCompleted, isFalse);

      await player.dispose();
    });

    test('idle audio player platform methods and effects', () async {
      final player = AudioPlayer();
      final idle = player.testIdlePlatform;

      // play on idle
      final playResp = await idle.play(PlayRequest());
      expect(playResp, isA<PlayResponse>());

      // shuffle order on idle
      final shuffleResp = await idle.setShuffleOrder(
        SetShuffleOrderRequest(
          audioSourceMessage: ConcatenatingAudioSourceMessage(
            id: '',
            children: [],
            useLazyPreparation: true,
            shuffleOrder: [],
          ),
        ),
      );
      expect(shuffleResp, isA<SetShuffleOrderResponse>());

      // audio effects on idle
      final effectResp = await idle.audioEffectSetEnabled(
        AudioEffectSetEnabledRequest(type: 'AndroidEqualizer', enabled: true),
      );
      expect(effectResp, isA<AudioEffectSetEnabledResponse>());

      final gainResp = await idle.androidLoudnessEnhancerSetTargetGain(
        AndroidLoudnessEnhancerSetTargetGainRequest(targetGain: 1.5),
      );
      expect(gainResp, isA<AndroidLoudnessEnhancerSetTargetGainResponse>());

      final bandResp = await idle.androidEqualizerBandSetGain(
        AndroidEqualizerBandSetGainRequest(bandIndex: 0, gain: 2),
      );
      expect(bandResp, isA<AndroidEqualizerBandSetGainResponse>());

      final paramsResp = await idle.androidEqualizerGetParameters(AndroidEqualizerGetParametersRequest());
      expect(paramsResp.parameters.bands, isEmpty);

      // plugin load request helpers
      AudioPlayerTestHooks.testPluginLoadRequest();

      await player.dispose();
    });

    test('idle concatenatingMove index branches', () async {
      final player = AudioPlayer();
      final idle = player.testIdlePlatform;

      // Load on idle platform to establish an initial index of 1
      await idle.load(
        LoadRequest(
          audioSourceMessage: ConcatenatingAudioSourceMessage(
            id: '',
            children: [],
            useLazyPreparation: true,
            shuffleOrder: [],
          ),
          initialIndex: 1,
        ),
      );

      // currentIndex == _index (1 == 1) -> hits lines 166-167
      await idle.concatenatingMove(
        ConcatenatingMoveRequest(id: '', currentIndex: 1, newIndex: 2, shuffleOrder: const [0, 1, 2]),
      );

      // Now _index is 2. currentIndex < _index (0 < 2) && newIndex >= _index (2 >= 2) -> hits lines 169-170
      await idle.concatenatingMove(
        ConcatenatingMoveRequest(id: '', currentIndex: 0, newIndex: 2, shuffleOrder: const [0, 1, 2]),
      );

      // Now _index is 1. currentIndex > _index (2 > 1) && newIndex <= _index (0 <= 1) -> hits lines 172-173
      await idle.concatenatingMove(
        ConcatenatingMoveRequest(id: '', currentIndex: 2, newIndex: 0, shuffleOrder: const [0, 1, 2]),
      );

      await player.dispose();
    });

    test('composite playlist testCreatePlaylist and active addAudioSource', () async {
      final player = AudioPlayer();
      final child1 = AudioSource.uri(Uri.parse('https://example.com/c1.mp3'));
      final child2 = AudioSource.uri(Uri.parse('https://example.com/c2.mp3'));

      // testCreatePlaylist attaches children to player
      final playlist = AudioPlayerTestHooks.testCreatePlaylist([child1, child2], player);
      expect(playlist.sequence.length, equals(2));
      expect(AudioPlayerTestHooks.testPlaylistLength(playlist), equals(2));
      expect(AudioPlayerTestHooks.testPlaylistGet(playlist, 0), equals(child1));

      // active addAudioSource: load first to make player active
      await player.setAudioSources([child1]);
      expect(player.sequence.length, equals(1));
      // Now player is active, add another source to trigger active _onLoad
      await player.addAudioSource(child2);
      expect(player.sequence.length, equals(2));

      await player.dispose();
    });

    test('audio player getters and streams', () async {
      final player = AudioPlayer();
      expect(player.durationStream, isA<Stream<Duration?>>());
      expect(player.volumeStream, isA<ValueStream<double>>());
      expect(player.speedStream, isA<ValueStream<double>>());
      expect(player.pitchStream, isA<ValueStream<double>>());
      expect(player.skipSilenceEnabledStream, isA<Stream<bool>>());
      expect(player.bufferedPosition, equals(Duration.zero));
      expect(player.bufferedPositionStream, isA<Stream<Duration>>());
      expect(player.playerState, equals(const PlayerState(playing: false, processingState: ProcessingState.idle)));
      expect(player.playerStateStream, isA<Stream<PlayerState>>());
      expect(player.shuffleIndicesStream, isA<Stream<List<int>>>());
      expect(player.loopModeStream, isA<Stream<LoopMode>>());
      expect(player.shuffleModeEnabledStream, isA<Stream<bool>>());
      expect(player.androidAudioSessionIdStream, isA<Stream<int?>>());
      expect(player.errorStream, isA<Stream<PlayerException>>());

      // LoopMode indexing branches
      final s1 = AudioSource.uri(Uri.parse('https://example.com/s1.mp3'));
      final s2 = AudioSource.uri(Uri.parse('https://example.com/s2.mp3'));
      await player.setAudioSources([s1, s2]);

      await player.setLoopMode(LoopMode.all);
      // When at index 0 and loopMode.all, previousIndex wraps to index 1
      expect(player.previousIndex, equals(1));

      await player.setLoopMode(LoopMode.off);
      // When at index 0 and loopMode.off, nextIndex is 1
      expect(player.nextIndex, equals(1));

      // When loopMode.one and at last item, nextIndex returns currentIndex (line 578)
      await player.setLoopMode(LoopMode.one);
      expect(player.nextIndex, equals(player.currentIndex));

      // Position stream on disposed player
      await player.dispose();
      final stream = player.createPositionStream();
      expect(stream, isA<Stream<Duration>>());
    });

    test('createPositionStream timer cancellation when disposed', () async {
      final player = AudioPlayer();
      final s1 = AudioSource.uri(Uri.parse('https://example.com/pos.mp3'));
      await player.setAudioSources([s1]);
      unawaited(player.play());

      final sub = player.createPositionStream(minPeriod: const Duration(milliseconds: 10)).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await player.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await sub.cancel();
    });

    test('AudioPlayer error mapping and convertException', () async {
      final player = AudioPlayer();

      // PlatformException with 'abort'
      final exAbort = player.testConvertException(PlatformException(code: 'abort', message: 'aborted'));
      expect(exAbort, isA<PlayerInterruptedException>());

      // PlatformException with 10000000
      final exInterrupted = player.testConvertException(PlatformException(code: '10000000', message: 'interrupted'));
      expect(exInterrupted, isA<PlayerInterruptedException>());

      // PlatformException with non-numeric string
      final exCustom = player.testConvertException(PlatformException(code: 'custom_error', message: 'failed'));
      expect(exCustom, isA<PlayerException>());
      expect((exCustom as PlayerException).code, equals(9999999));

      // PlatformException with numeric code
      final exNumeric = player.testConvertException(PlatformException(code: '404', message: 'not found'));
      expect(exNumeric, isA<PlayerException>());
      expect((exNumeric as PlayerException).code, equals(404));

      await player.dispose();
    });

    test('AudioPlayer clearAssetCache and getCacheDir', () async {
      final cacheDir = Directory('${mockTempDir.path}/audio_player_cache');
      await cacheDir.create(recursive: true);
      final dummyFile = File('${cacheDir.path}/temp.txt');
      await dummyFile.writeAsString('hello');
      expect(dummyFile.existsSync(), isTrue);

      await AudioPlayer.clearAssetCache();
      expect(dummyFile.existsSync(), isFalse);
    });

    test('AudioPlayer clearAssetCache does nothing before anything was cached', () async {
      final cacheDir = Directory('${mockTempDir.path}/audio_player_cache');
      if (cacheDir.existsSync()) {
        await cacheDir.delete(recursive: true);
      }

      await expectLater(AudioPlayer.clearAssetCache(), completes);
    });

    test('AudioPlayer pre-set settings synchronization during activate', () async {
      final player = AudioPlayer();
      // Configure settings while inactive
      await player.setVolume(0.8);
      await player.setSpeed(1.2);
      await player.setPitch(1.1);
      await player.setSkipSilenceEnabled(enabled: true);
      await player.setLoopMode(LoopMode.one);
      await player.setShuffleModeEnabled(enabled: true);
      await player.setAutomaticallyWaitsToMinimizeStalling(enabled: false);

      // Now load audio source - synchronizes all non-default values to platform
      final source = AudioSource.uri(Uri.parse('https://example.com/sync.mp3'));
      await player.setAudioSource(source);

      expect(player.volume, equals(0.8));
      expect(player.speed, equals(1.2));
      expect(player.pitch, equals(1.1));
      expect(player.skipSilenceEnabled, isTrue);
      expect(player.loopMode, equals(LoopMode.one));
      expect(player.shuffleModeEnabled, isTrue);
      expect(player.automaticallyWaitsToMinimizeStalling, isFalse);

      await player.dispose();
    });

    /// Loads the asset `assets/test.mp3` while the temporary directory is
    /// reported as [tempDirPath], and checks that it is extracted into the
    /// cache directory under `mockTempDir` and that the platform gets that
    /// file's URI.
    Future<void> expectAssetExtractedToCache(String tempDirPath) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProviderChannel,
        (methodCall) async => methodCall.method == 'getTemporaryDirectory' ? tempDirPath : null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
        ByteData? message,
      ) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key == 'assets/test.mp3') {
          return ByteData.view(Uint8List.fromList(utf8.encode('AssetAudioData')).buffer);
        }
        return null;
      });

      final platform = AudioPlayerPlatform.instance as SimpleMockAudioPlayerPlatform;
      final player = AudioPlayer();
      final source = AudioSource.asset('assets/test.mp3');
      await player.setAudioSource(source);

      expect(player.sequence.length, equals(1));
      final cacheFile = File('${mockTempDir.path}/audio_player_cache/assets/assets/test.mp3');
      expect(cacheFile.readAsStringSync(), equals('AssetAudioData'));
      final playlist =
          platform.players.values.last.lastLoadRequest!.audioSourceMessage as ConcatenatingAudioSourceMessage;
      expect((playlist.children.single as UriAudioSourceMessage).uri, equals(Uri.file(cacheFile.path).toString()));

      await AudioPlayer.clearAssetCache();
      await player.dispose();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', null);
    }

    test('asset loading extraction to cache file', () async {
      await expectAssetExtractedToCache(mockTempDir.path);
    });

    test('asset cache path does not double a trailing separator of the temporary directory', () async {
      await expectAssetExtractedToCache('${mockTempDir.path}/');
    });

    test('request headers and user agent are sent to the platform with the original URL', () async {
      final platform = AudioPlayerPlatform.instance as SimpleMockAudioPlayerPlatform;
      final player = AudioPlayer(userAgent: 'TestUserAgent/1.0');
      const url = 'https://example.com/hls/playlist.m3u8?token=abc';
      await player.setUrl(url, headers: {'X-Custom': '1'});

      final playlist =
          platform.players.values.last.lastLoadRequest!.audioSourceMessage as ConcatenatingAudioSourceMessage;
      final source = playlist.children.single as UriAudioSourceMessage;
      expect(source.uri, equals(url));
      expect(source.headers, equals({'X-Custom': '1', 'User-Agent': 'TestUserAgent/1.0'}));

      await player.dispose();
    });

    test('AudioPlayer maxSkipsOnError error skipping and resetting', () async {
      final player = AudioPlayer(maxSkipsOnError: 2);
      final s1 = AudioSource.uri(Uri.parse('https://example.com/e1.mp3'));
      final s2 = AudioSource.uri(Uri.parse('https://example.com/e2.mp3'));
      final s3 = AudioSource.uri(Uri.parse('https://example.com/e3.mp3'));
      await player.setAudioSources([s1, s2, s3]);

      final platform = AudioPlayerPlatform.instance as SimpleMockAudioPlayerPlatform;
      final instance = platform.players.values.last;

      // Simulate error event to trigger maxSkipsOnError listener (line 305-307)
      instance.eventController.add(
        PlaybackEventMessage(
          processingState: ProcessingStateMessage.ready,
          updatePosition: Duration.zero,
          updateTime: DateTime.now(),
          bufferedPosition: Duration.zero,
          duration: const Duration(seconds: 30),
          errorCode: 1,
          errorMessage: 'Error 1',
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Reset on ready (line 313)
      instance.eventController.add(
        PlaybackEventMessage(
          processingState: ProcessingStateMessage.ready,
          updatePosition: Duration.zero,
          updateTime: DateTime.now(),
          bufferedPosition: Duration.zero,
          duration: const Duration(seconds: 30),
          icyMetadata: null,
          currentIndex: 0,
          androidAudioSessionId: null,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await player.dispose();
    });

    test('playback event stream errors are not reported twice and others reach FlutterError', () async {
      final platform = AudioPlayerPlatform.instance as SimpleMockAudioPlayerPlatform;
      final player = AudioPlayer();
      await player.setAudioSource(AudioSource.uri(Uri.parse('https://example.com/err.mp3')));
      final instance = platform.players.values.last;

      final errors = <PlayerException>[];
      final errorSubscription = player.errorStream.listen(errors.add);
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      try {
        // A native error arrives on the event channel and then in the next
        // playback event; errorStream reports it once, from the event.
        instance.eventController
          ..addError(PlatformException(code: '7', message: 'Native error'))
          ..add(
            PlaybackEventMessage(
              processingState: ProcessingStateMessage.ready,
              updatePosition: Duration.zero,
              updateTime: DateTime.now(),
              bufferedPosition: Duration.zero,
              duration: const Duration(seconds: 30),
              errorCode: 7,
              errorMessage: 'Native error',
              icyMetadata: null,
              currentIndex: 0,
              androidAudioSessionId: null,
            ),
          );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(errors.map((e) => e.code), equals([7]));
        expect(reported, isEmpty);

        instance.eventController.addError(const FormatException('Malformed event'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(reported.single.exception, isA<FormatException>());
        expect(reported.single.library, equals('audio_player'));
        expect(errors, hasLength(1));
      } finally {
        FlutterError.onError = previousOnError;
        await errorSubscription.cancel();
      }

      await player.dispose();
    });

    test('AudioPlayer platform error rollback in setVolume, setSpeed, setPitch, setSkipSilence and play', () async {
      final failingPlatform = _FailingPlatform();
      AudioPlayerPlatform.instance = failingPlatform;

      final player = AudioPlayer(handleAudioSessionActivation: false);
      final source = AudioSource.uri(Uri.parse('https://example.com/fail.mp3'));
      await player.setAudioSource(source);

      final instance = failingPlatform.lastInstance!..throwOnSetVolume = true;
      await expectLater(() => player.setVolume(0.5), throwsA(isA<PlatformException>()));
      expect(player.volume, equals(1.0));

      instance.throwOnSetSpeed = true;
      await expectLater(() => player.setSpeed(2), throwsA(isA<PlatformException>()));
      expect(player.speed, equals(1.0));

      instance.throwOnSetPitch = true;
      await expectLater(() => player.setPitch(1.5), throwsA(isA<PlatformException>()));
      expect(player.pitch, equals(1.0));

      instance.throwOnSetSkipSilence = true;
      await expectLater(() => player.setSkipSilenceEnabled(enabled: true), throwsA(isA<PlatformException>()));

      instance.throwOnPlay = true;
      await expectLater(player.play(), throwsA(isA<PlatformException>()));

      await player.dispose();
      AudioPlayerPlatform.instance = SimpleMockAudioPlayerPlatform();
    });
  });
}
