import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:audio_player/src/platform_interface/method_channel_audio_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mainChannel = MethodChannel('uz.plugin.audio_player.methods');

  group('MethodChannelAudioPlayerPlatform', () {
    test('init, disposePlayer, disposeAllPlayers', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(mainChannel, (call) async {
        calls.add(call);
        if (call.method == 'init') {
          return null;
        } else if (call.method == 'disposePlayer') {
          return <dynamic, dynamic>{};
        } else if (call.method == 'disposeAllPlayers') {
          return <dynamic, dynamic>{};
        }
        return null;
      });

      final platform = MethodChannelAudioPlayerPlatform();
      final playerInstance = await platform.init(InitRequest(id: 'test_player_1'));
      expect(playerInstance, isA<MethodChannelAudioPlayerInstance>());
      expect(playerInstance.id, equals('test_player_1'));

      final disposePlayerResp = await platform.disposePlayer(DisposePlayerRequest(id: 'test_player_1'));
      expect(disposePlayerResp, isA<DisposePlayerResponse>());

      final disposeAllResp = await platform.disposeAllPlayers(DisposeAllPlayersRequest());
      expect(disposeAllResp, isA<DisposeAllPlayersResponse>());

      expect(calls.map((c) => c.method).toList(), equals(['init', 'disposePlayer', 'disposeAllPlayers']));
      messenger.setMockMethodCallHandler(mainChannel, null);
    });

    test('null reply throws PlatformException', () {
      messenger.setMockMethodCallHandler(mainChannel, (call) async => null);
      final platform = MethodChannelAudioPlayerPlatform();
      expect(
        () => platform.disposePlayer(DisposePlayerRequest(id: 'p1')),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'null-reply')),
      );
      messenger.setMockMethodCallHandler(mainChannel, null);
    });
  });

  group('MethodChannelAudioPlayerInstance', () {
    const playerId = 'instance_1';
    const instanceChannel = MethodChannel('uz.plugin.audio_player.methods.$playerId');

    test('all instance methods and null-reply handling', () async {
      final methodCalls = <String>[];
      var returnNull = false;

      messenger.setMockMethodCallHandler(instanceChannel, (call) async {
        methodCalls.add(call.method);
        if (returnNull) {
          return null;
        }

        if (call.method == 'androidEqualizerGetParameters') {
          return <dynamic, dynamic>{
            'parameters': <dynamic, dynamic>{'minDecibels': 0.0, 'maxDecibels': 10.0, 'bands': <dynamic>[]},
          };
        }
        return <dynamic, dynamic>{};
      });

      final instance = MethodChannelAudioPlayerInstance(playerId);

      await instance.load(
        LoadRequest(
          audioSourceMessage: ConcatenatingAudioSourceMessage(
            id: 'cat',
            children: [],
            useLazyPreparation: true,
            shuffleOrder: [],
          ),
          initialIndex: 0,
          initialPosition: Duration.zero,
        ),
      );
      await instance.play(PlayRequest());
      await instance.pause(PauseRequest());
      await instance.setVolume(SetVolumeRequest(volume: 0.5));
      await instance.setSpeed(SetSpeedRequest(speed: 1.2));
      await instance.setPitch(SetPitchRequest(pitch: 1.1));
      await instance.setSkipSilence(SetSkipSilenceRequest(enabled: true));
      await instance.setLoopMode(SetLoopModeRequest(loopMode: LoopModeMessage.one));
      await instance.setShuffleMode(SetShuffleModeRequest(shuffleMode: ShuffleModeMessage.all));
      await instance.setShuffleOrder(
        SetShuffleOrderRequest(
          audioSourceMessage: ConcatenatingAudioSourceMessage(
            id: 's',
            children: [],
            useLazyPreparation: true,
            shuffleOrder: [],
          ),
        ),
      );
      await instance.setAutomaticallyWaitsToMinimizeStalling(
        SetAutomaticallyWaitsToMinimizeStallingRequest(enabled: true),
      );
      await instance.setCanUseNetworkResourcesForLiveStreamingWhilePaused(
        SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest(enabled: true),
      );
      await instance.setPreferredPeakBitRate(SetPreferredPeakBitRateRequest(bitRate: 1000));
      await instance.setAllowsExternalPlayback(SetAllowsExternalPlaybackRequest(allowsExternalPlayback: true));
      await instance.seek(SeekRequest(position: const Duration(seconds: 5), index: 0));
      await instance.setAndroidAudioAttributes(SetAndroidAudioAttributesRequest(contentType: 1, flags: 0, usage: 1));
      await instance.concatenatingInsertAll(
        ConcatenatingInsertAllRequest(id: 'c', index: 0, children: [], shuffleOrder: []),
      );
      await instance.concatenatingRemoveRange(
        ConcatenatingRemoveRangeRequest(id: 'c', startIndex: 0, endIndex: 1, shuffleOrder: []),
      );
      await instance.concatenatingMove(
        ConcatenatingMoveRequest(id: 'c', currentIndex: 0, newIndex: 1, shuffleOrder: []),
      );
      await instance.audioEffectSetEnabled(AudioEffectSetEnabledRequest(type: 'AndroidEqualizer', enabled: true));
      await instance.androidLoudnessEnhancerSetTargetGain(AndroidLoudnessEnhancerSetTargetGainRequest(targetGain: 1.5));
      final eqParams = await instance.androidEqualizerGetParameters(AndroidEqualizerGetParametersRequest());
      expect(eqParams.parameters.bands, isEmpty);
      await instance.androidEqualizerBandSetGain(AndroidEqualizerBandSetGainRequest(bandIndex: 0, gain: 2));
      await instance.dispose(DisposeRequest());

      expect(
        methodCalls,
        equals([
          'load',
          'play',
          'pause',
          'setVolume',
          'setSpeed',
          'setPitch',
          'setSkipSilence',
          'setLoopMode',
          'setShuffleMode',
          'setShuffleOrder',
          'setAutomaticallyWaitsToMinimizeStalling',
          'setCanUseNetworkResourcesForLiveStreamingWhilePaused',
          'setPreferredPeakBitRate',
          'setAllowsExternalPlayback',
          'seek',
          'setAndroidAudioAttributes',
          'concatenatingInsertAll',
          'concatenatingRemoveRange',
          'concatenatingMove',
          'audioEffectSetEnabled',
          'androidLoudnessEnhancerSetTargetGain',
          'androidEqualizerGetParameters',
          'androidEqualizerBandSetGain',
          'dispose',
        ]),
      );

      returnNull = true;
      expect(
        () => instance.play(PlayRequest()),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'null-reply')),
      );

      messenger.setMockMethodCallHandler(instanceChannel, null);
    });

    test('event streams are accessible', () {
      final instance = MethodChannelAudioPlayerInstance('test_streams');
      expect(instance.playbackEventMessageStream, isNotNull);
      expect(instance.playerDataMessageStream, isNotNull);
    });
  });
}
