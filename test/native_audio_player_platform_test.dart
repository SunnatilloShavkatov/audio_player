import 'dart:convert';

import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:audio_player/src/platform_interface/native_audio_player_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Call {
  new(this.playerId, this.method, this.request);
  final String? playerId;
  final String method;
  final String request;
}

class _FakeTransport extends NativeAudioPlayerTransport {
  final calls = <_Call>[];
  String Function(_Call call) reply = (call) => call.method == 'androidEqualizerGetParameters'
      ? '{"parameters":{"minDecibels":0,"maxDecibels":10,"bands":[]}}'
      : '{}';
  Exception? failure;
  int listenCount = 0;

  @override
  Future<String> send(String? playerId, String method, String request) async {
    final call = _Call(playerId, method, request);
    calls.add(call);
    final error = failure;
    if (error != null) {
      throw error;
    }
    return reply(call);
  }

  @override
  void listen() => listenCount++;
}

void main() {
  group('NativeAudioPlayerPlatform', () {
    test('init, disposePlayer, disposeAllPlayers', () async {
      final transport = _FakeTransport();
      final platform = NativeAudioPlayerPlatform(transport);
      final instance = await platform.init(InitRequest(id: 'p1'));
      expect(instance, isA<NativeAudioPlayerInstance>());
      expect(instance.id, 'p1');
      expect(transport.listenCount, 1);
      expect(jsonDecode(transport.calls.single.request), containsPair('id', 'p1'));

      await platform.disposePlayer(DisposePlayerRequest(id: 'p1'));
      await platform.disposeAllPlayers(DisposeAllPlayersRequest());
      expect(transport.calls.map((c) => c.method), ['init', 'disposePlayer', 'disposeAllPlayers']);
      expect(transport.calls.every((c) => c.playerId == null), isTrue);
      expect(transport.listenCount, 1);
    });

    test('a failed init throws and stops routing events', () async {
      final transport = _FakeTransport()..failure = PlatformException(code: 'error');
      final platform = NativeAudioPlayerPlatform(transport);
      await expectLater(platform.init(InitRequest(id: 'p1')), throwsA(isA<PlatformException>()));
    });

    test('an unreadable or non-map reply throws PlatformException', () async {
      final transport = _FakeTransport()..reply = (_) => 'null';
      final platform = NativeAudioPlayerPlatform(transport);
      await expectLater(
        platform.disposePlayer(DisposePlayerRequest(id: 'p1')),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'null-reply')),
      );
      transport.reply = (_) => '{oops';
      await expectLater(
        platform.disposePlayer(DisposePlayerRequest(id: 'p1')),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'bad-reply')),
      );
    });
  });

  group('NativeAudioPlayerInstance', () {
    test('all instance methods go to the player with their method names', () async {
      final transport = _FakeTransport();
      final instance = NativeAudioPlayerInstance('instance_1', transport);

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
        transport.calls.map((c) => c.method).toList(),
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

      expect(transport.calls.every((c) => c.playerId == 'instance_1'), isTrue);
    });

    test('native errors become PlatformExceptions with decoded details', () {
      final error = NativeAudioPlayerTransport.platformException('7', 'boom', '{"index":2}');
      expect(error.code, '7');
      expect(error.details, {'index': 2});
      expect(NativeAudioPlayerTransport.platformException('e', null, 'plain').details, 'plain');
      expect(NativeAudioPlayerTransport.platformException('e', null, '{bad').details, '{bad');
    });

    test('events are routed to the stream of their player', () async {
      final transport = _FakeTransport()..attach('a');
      final instance = NativeAudioPlayerInstance('a', transport);
      final events = <PlaybackEventMessage>[];
      final data = <PlayerDataMessage>[];
      final errors = <Object>[];
      final subs = [
        instance.playbackEventMessageStream.listen(events.add, onError: errors.add),
        instance.playerDataMessageStream.listen(data.add),
      ];

      transport
        ..onPlaybackEvent(
          'a',
          jsonEncode({
            'processingState': 3,
            'updateTime': 1000,
            'updatePosition': 5,
            'bufferedPosition': 6,
            'duration': 7,
            'icyMetadata': null,
            'currentIndex': 0,
            'androidAudioSessionId': null,
            'errorCode': null,
            'errorMessage': null,
          }),
        )
        ..onPlaybackEvent('other', '{}')
        ..onPlaybackEvent('a', '{"processingState":"bad"}')
        ..onPlaybackError('a', '5', 'message', null)
        ..onPlayerData('a', '{"playing":false,"volume":1}');
      await Future<void>.delayed(Duration.zero);

      expect(events.single.processingState, ProcessingStateMessage.ready);
      expect(events.single.duration, const Duration(microseconds: 7));
      expect(errors, hasLength(2));
      expect(errors.last, isA<PlatformException>().having((e) => e.code, 'code', '5'));
      expect(data.single.playing, isFalse);
      expect(data.single.volume, 1.0);

      transport.detach('a');
      for (final sub in subs) {
        await sub.cancel();
      }
    });
  });
}
