import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnimplementedPlatform extends AudioPlayerPlatform;

class _UnimplementedPlayerInstance extends AudioPlayerInstancePlatform {
  new(super.id);
}

void main() {
  group('AudioPlayerPlatform base unimplemented methods', () {
    test('methods throw UnimplementedError', () {
      final platform = _UnimplementedPlatform();
      expect(() => platform.init(InitRequest(id: '1')), throwsUnimplementedError);
      expect(() => platform.disposePlayer(DisposePlayerRequest(id: '1')), throwsUnimplementedError);
      expect(() => platform.disposeAllPlayers(DisposeAllPlayersRequest()), throwsUnimplementedError);
    });

    test('instance getter and setter', () {
      final original = AudioPlayerPlatform.instance;
      final newPlatform = _UnimplementedPlatform();
      AudioPlayerPlatform.instance = newPlatform;
      expect(AudioPlayerPlatform.instance, equals(newPlatform));
      AudioPlayerPlatform.instance = original;
    });
  });

  group('AudioPlayerInstancePlatform base unimplemented methods', () {
    test('methods throw UnimplementedError', () async {
      final instance = _UnimplementedPlayerInstance('id');
      expect(() => instance.playbackEventMessageStream, throwsUnimplementedError);
      expect(await instance.playerDataMessageStream.isEmpty, isTrue);

      final dummySource = ConcatenatingAudioSourceMessage(
        id: 'c',
        children: [],
        useLazyPreparation: true,
        shuffleOrder: [],
      );
      expect(() => instance.load(LoadRequest(audioSourceMessage: dummySource)), throwsUnimplementedError);
      expect(() => instance.play(PlayRequest()), throwsUnimplementedError);
      expect(() => instance.pause(PauseRequest()), throwsUnimplementedError);
      expect(() => instance.setVolume(SetVolumeRequest(volume: 1)), throwsUnimplementedError);
      expect(() => instance.setSpeed(SetSpeedRequest(speed: 1)), throwsUnimplementedError);
      expect(() => instance.setPitch(SetPitchRequest(pitch: 1)), throwsUnimplementedError);
      expect(() => instance.setSkipSilence(SetSkipSilenceRequest(enabled: true)), throwsUnimplementedError);
      expect(() => instance.setLoopMode(SetLoopModeRequest(loopMode: LoopModeMessage.off)), throwsUnimplementedError);
      expect(
        () => instance.setShuffleMode(SetShuffleModeRequest(shuffleMode: ShuffleModeMessage.none)),
        throwsUnimplementedError,
      );
      expect(
        () => instance.setShuffleOrder(SetShuffleOrderRequest(audioSourceMessage: dummySource)),
        throwsUnimplementedError,
      );
      expect(
        () => instance.setAutomaticallyWaitsToMinimizeStalling(
          SetAutomaticallyWaitsToMinimizeStallingRequest(enabled: true),
        ),
        throwsUnimplementedError,
      );
      expect(
        () => instance.setCanUseNetworkResourcesForLiveStreamingWhilePaused(
          SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest(enabled: true),
        ),
        throwsUnimplementedError,
      );
      expect(
        () => instance.setPreferredPeakBitRate(SetPreferredPeakBitRateRequest(bitRate: 100)),
        throwsUnimplementedError,
      );
      expect(
        () => instance.setAllowsExternalPlayback(SetAllowsExternalPlaybackRequest(allowsExternalPlayback: true)),
        throwsUnimplementedError,
      );
      expect(() => instance.seek(SeekRequest()), throwsUnimplementedError);
      expect(
        () => instance.setAndroidAudioAttributes(SetAndroidAudioAttributesRequest(contentType: 1, flags: 0, usage: 1)),
        throwsUnimplementedError,
      );
      expect(
        () => instance.concatenatingInsertAll(
          ConcatenatingInsertAllRequest(id: 'c', index: 0, children: [], shuffleOrder: []),
        ),
        throwsUnimplementedError,
      );
      expect(
        () => instance.concatenatingRemoveRange(
          ConcatenatingRemoveRangeRequest(id: 'c', startIndex: 0, endIndex: 1, shuffleOrder: []),
        ),
        throwsUnimplementedError,
      );
      expect(
        () => instance.concatenatingMove(
          ConcatenatingMoveRequest(id: 'c', currentIndex: 0, newIndex: 1, shuffleOrder: []),
        ),
        throwsUnimplementedError,
      );
      expect(
        () => instance.audioEffectSetEnabled(AudioEffectSetEnabledRequest(type: 'AndroidEqualizer', enabled: true)),
        throwsUnimplementedError,
      );
      expect(
        () => instance.androidLoudnessEnhancerSetTargetGain(AndroidLoudnessEnhancerSetTargetGainRequest(targetGain: 1)),
        throwsUnimplementedError,
      );
      expect(
        () => instance.androidEqualizerGetParameters(AndroidEqualizerGetParametersRequest()),
        throwsUnimplementedError,
      );
      expect(
        () => instance.androidEqualizerBandSetGain(AndroidEqualizerBandSetGainRequest(bandIndex: 0, gain: 1)),
        throwsUnimplementedError,
      );
      expect(() => instance.dispose(DisposeRequest()), throwsUnimplementedError);
      expect(
        () => instance.setWebCrossOrigin(SetWebCrossOriginRequest(crossOrigin: WebCrossOriginMessage.anonymous)),
        throwsUnimplementedError,
      );
      expect(() => instance.setWebSinkId(SetWebSinkIdRequest(sinkId: 'sink')), throwsUnimplementedError);
    });
  });

  group('Request and Response Messages serialisation', () {
    test('InitRequest and Dispose Requests', () {
      final req = InitRequest(
        id: 'p1',
        audioLoadConfiguration: AudioLoadConfigurationMessage(
          darwinLoadControl: DarwinLoadControlMessage(
            automaticallyWaitsToMinimizeStalling: true,
            preferredForwardBufferDuration: const Duration(seconds: 10),
            canUseNetworkResourcesForLiveStreamingWhilePaused: false,
            preferredPeakBitRate: 50000,
          ),
          androidLoadControl: AndroidLoadControlMessage(
            minBufferDuration: const Duration(seconds: 10),
            maxBufferDuration: const Duration(seconds: 20),
            bufferForPlaybackDuration: const Duration(seconds: 2),
            bufferForPlaybackAfterRebufferDuration: const Duration(seconds: 5),
            targetBufferBytes: 500,
            prioritizeTimeOverSizeThresholds: true,
            backBufferDuration: const Duration(seconds: 5),
          ),
          androidLivePlaybackSpeedControl: AndroidLivePlaybackSpeedControlMessage(
            fallbackMinPlaybackSpeed: 0.9,
            fallbackMaxPlaybackSpeed: 1.1,
            minUpdateInterval: const Duration(seconds: 1),
            proportionalControlFactor: 1,
            maxLiveOffsetErrorForUnitSpeed: const Duration(milliseconds: 20),
            targetLiveOffsetIncrementOnRebuffer: const Duration(milliseconds: 500),
            minPossibleLiveOffsetSmoothingFactor: 0.99,
          ),
        ),
        androidAudioOffloadPreferences: AndroidAudioOffloadPreferencesMessage(
          audioOffloadMode: AndroidAudioOffloadModeMessage.enabled,
          isGaplessSupportRequired: true,
          isSpeedChangeSupportRequired: true,
        ),
      );

      final map = req.toMap();
      expect(map['id'], equals('p1'));
      expect(map['audioLoadConfiguration'], isA<Map<dynamic, dynamic>>());
      expect(map['androidAudioOffloadPreferences'], isA<Map<dynamic, dynamic>>());

      final dispReq = DisposePlayerRequest(id: 'p1');
      expect(dispReq.toMap()['id'], equals('p1'));
      expect(DisposePlayerResponse.fromMap(<dynamic, dynamic>{}), isA<DisposePlayerResponse>());

      expect(DisposeAllPlayersRequest().toMap(), isA<Map<dynamic, dynamic>>());
      expect(DisposeAllPlayersResponse.fromMap(<dynamic, dynamic>{}), isA<DisposeAllPlayersResponse>());
    });

    test('LoadRequest and Response', () {
      final req = LoadRequest(
        audioSourceMessage: ProgressiveAudioSourceMessage(
          id: 'src',
          uri: 'https://example.com/audio.mp3',
          headers: {'auth': 'token'},
          options: const ProgressiveAudioSourceOptionsMessage(
            darwinAssetOptions: DarwinAssetOptionsMessage(preferPreciseDurationAndTiming: true),
            androidExtractorOptions: AndroidExtractorOptionsMessage(
              constantBitrateSeekingEnabled: true,
              constantBitrateSeekingAlwaysEnabled: false,
              mp3Flags: 1,
            ),
          ),
        ),
        initialIndex: 2,
        initialPosition: const Duration(seconds: 5),
      );
      final map = req.toMap();
      expect(map['initialIndex'], equals(2));
      expect(map['initialPosition'], equals(5000000));
      final sourceMap = map['audioSource'] as Map<dynamic, dynamic>;
      expect(sourceMap['uri'], equals('https://example.com/audio.mp3'));

      final resp = LoadResponse.fromMap(<dynamic, dynamic>{'duration': 180000000});
      expect(resp.duration, equals(const Duration(minutes: 3)));
    });

    test('AudioSourceMessage variants serialisation', () {
      final dash = DashAudioSourceMessage(id: 'dash', uri: 'https://dash.mpd', headers: {'h': '1'});
      expect(dash.toMap()['uri'], equals('https://dash.mpd'));

      final hls = HlsAudioSourceMessage(id: 'hls', uri: 'https://hls.m3u8');
      expect(hls.toMap()['uri'], equals('https://hls.m3u8'));

      final silence = SilenceAudioSourceMessage(id: 'silence', duration: const Duration(seconds: 10));
      expect(silence.toMap()['duration'], equals(10000000));

      final clipping = ClippingAudioSourceMessage(
        id: 'clip',
        child: ProgressiveAudioSourceMessage(id: 'child', uri: 'https://foo.mp3'),
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 8),
      );
      final clipMap = clipping.toMap();
      expect(clipMap['start'], equals(2000000));
      expect(clipMap['end'], equals(8000000));

      final looping = LoopingAudioSourceMessage(
        id: 'loop',
        child: ProgressiveAudioSourceMessage(id: 'c2', uri: 'https://foo2.mp3'),
        count: 5,
      );
      expect(looping.toMap()['count'], equals(5));

      final cat = ConcatenatingAudioSourceMessage(
        id: 'cat',
        children: [dash, hls, silence, clipping, looping],
        useLazyPreparation: true,
        shuffleOrder: [0, 1, 2, 3, 4],
      );
      final catMap = cat.toMap();
      expect((catMap['children'] as List<dynamic>).length, equals(5));
      expect(catMap['useLazyPreparation'], isTrue);
      expect(catMap['shuffleOrder'], equals([0, 1, 2, 3, 4]));
    });

    test('Play, Pause, SetVolume, SetSpeed, SetPitch, SetSkipSilence', () {
      expect(PlayRequest().toMap(), isA<Map<dynamic, dynamic>>());
      expect(PlayResponse.fromMap(<dynamic, dynamic>{}), isA<PlayResponse>());

      expect(PauseRequest().toMap(), isA<Map<dynamic, dynamic>>());
      expect(PauseResponse.fromMap(<dynamic, dynamic>{}), isA<PauseResponse>());

      final vol = SetVolumeRequest(volume: 0.8);
      expect(vol.toMap()['volume'], equals(0.8));
      expect(SetVolumeResponse.fromMap(<dynamic, dynamic>{}), isA<SetVolumeResponse>());

      final spd = SetSpeedRequest(speed: 1.5);
      expect(spd.toMap()['speed'], equals(1.5));
      expect(SetSpeedResponse.fromMap(<dynamic, dynamic>{}), isA<SetSpeedResponse>());

      final pitch = SetPitchRequest(pitch: 1.2);
      expect(pitch.toMap()['pitch'], equals(1.2));
      expect(SetPitchResponse.fromMap(<dynamic, dynamic>{}), isA<SetPitchResponse>());

      final skip = SetSkipSilenceRequest(enabled: true);
      expect(skip.toMap()['enabled'], isTrue);
      expect(SetSkipSilenceResponse.fromMap(<dynamic, dynamic>{}), isA<SetSkipSilenceResponse>());
    });

    test('LoopMode, ShuffleMode, ShuffleOrder, Seek', () {
      final loop = SetLoopModeRequest(loopMode: LoopModeMessage.all);
      expect(loop.toMap()['loopMode'], equals(LoopModeMessage.all.index));
      expect(SetLoopModeResponse.fromMap(<dynamic, dynamic>{}), isA<SetLoopModeResponse>());

      final shuf = SetShuffleModeRequest(shuffleMode: ShuffleModeMessage.all);
      expect(shuf.toMap()['shuffleMode'], equals(ShuffleModeMessage.all.index));
      expect(SetShuffleModeResponse.fromMap(<dynamic, dynamic>{}), isA<SetShuffleModeResponse>());

      final order = SetShuffleOrderRequest(
        audioSourceMessage: ConcatenatingAudioSourceMessage(
          id: 's',
          children: [],
          useLazyPreparation: true,
          shuffleOrder: [],
        ),
      );
      expect(order.toMap()['audioSource'], isA<Map<dynamic, dynamic>>());
      expect(SetShuffleOrderResponse.fromMap(<dynamic, dynamic>{}), isA<SetShuffleOrderResponse>());

      final seek = SeekRequest(position: const Duration(seconds: 15), index: 3);
      final seekMap = seek.toMap();
      expect(seekMap['position'], equals(15000000));
      expect(seekMap['index'], equals(3));
      expect(SeekResponse.fromMap(<dynamic, dynamic>{}), isA<SeekResponse>());
    });

    test('Stalling, BitRate, ExternalPlayback, NetworkResources, AndroidAudioAttributes', () {
      final stall = SetAutomaticallyWaitsToMinimizeStallingRequest(enabled: false);
      expect(stall.toMap()['enabled'], isFalse);
      expect(
        SetAutomaticallyWaitsToMinimizeStallingResponse.fromMap(<dynamic, dynamic>{}),
        isA<SetAutomaticallyWaitsToMinimizeStallingResponse>(),
      );

      final liveNet = SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest(enabled: true);
      expect(liveNet.toMap()['enabled'], isTrue);
      expect(
        SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse.fromMap(<dynamic, dynamic>{}),
        isA<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>(),
      );

      final br = SetPreferredPeakBitRateRequest(bitRate: 256000);
      expect(br.toMap()['bitRate'], equals(256000));
      expect(SetPreferredPeakBitRateResponse.fromMap(<dynamic, dynamic>{}), isA<SetPreferredPeakBitRateResponse>());

      final ext = SetAllowsExternalPlaybackRequest(allowsExternalPlayback: true);
      expect(ext.toMap()['allowsExternalPlayback'], isTrue);
      expect(SetAllowsExternalPlaybackResponse.fromMap(<dynamic, dynamic>{}), isA<SetAllowsExternalPlaybackResponse>());

      final attr = SetAndroidAudioAttributesRequest(contentType: 2, flags: 1, usage: 3);
      final attrMap = attr.toMap();
      expect(attrMap['contentType'], equals(2));
      expect(attrMap['flags'], equals(1));
      expect(attrMap['usage'], equals(3));
      expect(SetAndroidAudioAttributesResponse.fromMap(<dynamic, dynamic>{}), isA<SetAndroidAudioAttributesResponse>());
    });

    test('Concatenating operations and Dispose', () {
      final insert = ConcatenatingInsertAllRequest(
        id: 'c',
        index: 1,
        children: [ProgressiveAudioSourceMessage(id: 'p', uri: 'https://p.mp3')],
        shuffleOrder: [0],
      );
      final insertMap = insert.toMap();
      expect(insertMap['id'], equals('c'));
      expect(insertMap['index'], equals(1));
      expect(insertMap['children'], hasLength(1));
      expect(ConcatenatingInsertAllResponse.fromMap(<dynamic, dynamic>{}), isA<ConcatenatingInsertAllResponse>());

      final remove = ConcatenatingRemoveRangeRequest(id: 'c', startIndex: 1, endIndex: 3, shuffleOrder: []);
      final removeMap = remove.toMap();
      expect(removeMap['startIndex'], equals(1));
      expect(removeMap['endIndex'], equals(3));
      expect(ConcatenatingRemoveRangeResponse.fromMap(<dynamic, dynamic>{}), isA<ConcatenatingRemoveRangeResponse>());

      final move = ConcatenatingMoveRequest(id: 'c', currentIndex: 2, newIndex: 4, shuffleOrder: []);
      final moveMap = move.toMap();
      expect(moveMap['currentIndex'], equals(2));
      expect(moveMap['newIndex'], equals(4));
      expect(ConcatenatingMoveResponse.fromMap(<dynamic, dynamic>{}), isA<ConcatenatingMoveResponse>());

      expect(DisposeRequest().toMap(), isA<Map<dynamic, dynamic>>());
      expect(DisposeResponse.fromMap(<dynamic, dynamic>{}), isA<DisposeResponse>());
    });

    test('Audio Effects and Equalizer messages', () {
      final effect = AudioEffectSetEnabledRequest(type: 'AndroidEqualizer', enabled: false);
      final effectMap = effect.toMap();
      expect(effectMap['type'], equals('AndroidEqualizer'));
      expect(effectMap['enabled'], isFalse);
      expect(AudioEffectSetEnabledResponse.fromMap(<dynamic, dynamic>{}), isA<AudioEffectSetEnabledResponse>());

      final le = AndroidLoudnessEnhancerSetTargetGainRequest(targetGain: 2.5);
      expect(le.toMap()['targetGain'], equals(2.5));
      expect(
        AndroidLoudnessEnhancerSetTargetGainResponse.fromMap(<dynamic, dynamic>{}),
        isA<AndroidLoudnessEnhancerSetTargetGainResponse>(),
      );

      final eqGet = AndroidEqualizerGetParametersRequest();
      expect(eqGet.toMap(), isA<Map<dynamic, dynamic>>());

      final eqParams = AndroidEqualizerGetParametersResponse.fromMap(<dynamic, dynamic>{
        'parameters': <dynamic, dynamic>{
          'minDecibels': -10.0,
          'maxDecibels': 10.0,
          'bands': <dynamic>[
            <dynamic, dynamic>{
              'index': 0,
              'lowerFrequency': 0.toDouble(),
              'upperFrequency': 1000.toDouble(),
              'centerFrequency': 500.toDouble(),
              'gain': 1.toDouble(),
            },
          ],
        },
      });
      expect(eqParams.parameters.bands.length, equals(1));
      expect(eqParams.parameters.bands.first.centerFrequency, equals(500));
      expect(eqParams.parameters.bands.first.index, equals(0));
      expect(eqParams.parameters.bands.first.gain, equals(1.0));
      expect(eqParams.parameters.minDecibels, equals(-10.0));
      expect(eqParams.parameters.maxDecibels, equals(10.0));

      final bandGain = AndroidEqualizerBandSetGainRequest(bandIndex: 0, gain: 3);
      final bandGainMap = bandGain.toMap();
      expect(bandGainMap['bandIndex'], equals(0));
      expect(bandGainMap['gain'], equals(3));
      expect(
        AndroidEqualizerBandSetGainResponse.fromMap(<dynamic, dynamic>{}),
        isA<AndroidEqualizerBandSetGainResponse>(),
      );
    });

    test('Web messages', () {
      final crossOrigin = SetWebCrossOriginRequest(crossOrigin: WebCrossOriginMessage.useCredentials);
      expect(crossOrigin.crossOrigin, equals(WebCrossOriginMessage.useCredentials));
      expect(SetWebCrossOriginResponse(), isA<SetWebCrossOriginResponse>());

      final sink = SetWebSinkIdRequest(sinkId: 'speaker');
      expect(sink.sinkId, equals('speaker'));
      expect(SetWebSinkIdResponse(), isA<SetWebSinkIdResponse>());
    });

    test('PlaybackEventMessage and PlayerDataMessage fromMap', () {
      final eventMap = <dynamic, dynamic>{
        'processingState': 3,
        'updatePosition': 4000000,
        'updateTime': 1000000,
        'bufferedPosition': 8000000,
        'duration': 300000000,
        'currentIndex': 1,
        'androidAudioSessionId': 1234,
        'errorCode': 404,
        'errorMessage': 'Not found',
        'icyMetadata': <dynamic, dynamic>{
          'info': <dynamic, dynamic>{'title': 'Title', 'url': 'https://stream'},
          'headers': <dynamic, dynamic>{
            'bitrate': 128,
            'genre': 'Jazz',
            'name': 'Radio',
            'metadataInterval': 1024,
            'url': 'https://stream',
            'isPublic': true,
          },
        },
      };

      final decoded = PlaybackEventMessage.fromMap(eventMap);
      expect(decoded.processingState, equals(ProcessingStateMessage.ready));
      expect(decoded.updatePosition, equals(const Duration(seconds: 4)));
      expect(decoded.bufferedPosition, equals(const Duration(seconds: 8)));
      expect(decoded.duration, equals(const Duration(minutes: 5)));
      expect(decoded.currentIndex, equals(1));
      expect(decoded.androidAudioSessionId, equals(1234));
      expect(decoded.errorCode, equals(404));
      expect(decoded.errorMessage, equals('Not found'));
      expect(decoded.icyMetadata?.info?.title, equals('Title'));
      expect(decoded.icyMetadata?.headers?.genre, equals('Jazz'));

      final dataMap = <dynamic, dynamic>{
        'playing': true,
        'volume': 0.9,
        'speed': 1.1,
        'pitch': 1.0,
        'loopMode': 1,
        'shuffleMode': 1,
      };
      final decodedData = PlayerDataMessage.fromMap(dataMap);
      expect(decodedData.playing, isTrue);
      expect(decodedData.volume, equals(0.9));
      expect(decodedData.speed, equals(1.1));
      expect(decodedData.pitch, equals(1.0));
      expect(decodedData.loopMode, equals(LoopModeMessage.one));
      expect(decodedData.shuffleMode, equals(ShuffleModeMessage.all));
    });

    test('Android equalizer and loudness enhancer toMap', () {
      final enhancerMsg = AndroidLoudnessEnhancerMessage(enabled: true, targetGain: 2.5);
      expect(enhancerMsg.toMap(), {'type': 'AndroidLoudnessEnhancer', 'enabled': true, 'targetGain': 2.5});

      final bandMsg = AndroidEqualizerBandMessage(
        index: 0,
        lowerFrequency: 100,
        upperFrequency: 200,
        centerFrequency: 150,
        gain: 3,
      );
      expect(bandMsg.toMap(), {
        'index': 0,
        'lowerFrequency': 100.0,
        'upperFrequency': 200.0,
        'centerFrequency': 150.0,
        'gain': 3.0,
      });

      final paramsMsg = AndroidEqualizerParametersMessage(minDecibels: -10, maxDecibels: 10, bands: [bandMsg]);
      expect(paramsMsg.toMap(), {
        'minDecibels': -10.0,
        'maxDecibels': 10.0,
        'bands': [bandMsg.toMap()],
      });

      final eqMsg = AndroidEqualizerMessage(enabled: true, parameters: paramsMsg);
      expect(eqMsg.toMap(), {'type': 'AndroidEqualizer', 'enabled': true, 'parameters': paramsMsg.toMap()});
    });
  });
}
