import 'dart:async';

import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class SimpleMockAudioPlayerPlatform extends Mock with MockPlatformInterfaceMixin implements AudioPlayerPlatform {
  final players = <String, SimpleMockAudioPlayerInstance>{};

  @override
  Future<AudioPlayerInstancePlatform> init(InitRequest request) async {
    final player = SimpleMockAudioPlayerInstance(request);
    players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    players.remove(request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

class SimpleMockAudioPlayerInstance extends AudioPlayerInstancePlatform {
  new(this.initRequest) : super(initRequest.id);

  final InitRequest initRequest;
  final eventController = StreamController<PlaybackEventMessage>.broadcast();
  final dataController = StreamController<PlayerDataMessage>.broadcast();
  LoadRequest? lastLoadRequest;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => dataController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    lastLoadRequest = request;
    String? url;
    final source = request.audioSourceMessage;
    if (source is ConcatenatingAudioSourceMessage && source.children.isNotEmpty) {
      final child = source.children.first;
      if (child is UriAudioSourceMessage) {
        url = child.uri;
      }
    } else if (source is UriAudioSourceMessage) {
      url = source.uri;
    }

    eventController.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updatePosition: Duration.zero,
        updateTime: DateTime.now(),
        bufferedPosition: Duration.zero,
        duration: const Duration(seconds: 30),
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
        currentIndex: request.initialIndex ?? 0,
        androidAudioSessionId: null,
      ),
    );
    return LoadResponse(duration: const Duration(seconds: 30));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async => SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async => SetShuffleOrderResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) async => SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(
    SetPreferredPeakBitRateRequest request,
  ) async => SetPreferredPeakBitRateResponse();

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
    SetAllowsExternalPlaybackRequest request,
  ) async => SetAllowsExternalPlaybackResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await eventController.close();
    await dataController.close();
    return DisposeResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest request,
  ) async => ConcatenatingInsertAllResponse();

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest request,
  ) async => ConcatenatingRemoveRangeResponse();

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
    ConcatenatingMoveRequest request,
  ) async => ConcatenatingMoveResponse();

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(
    AudioEffectSetEnabledRequest request,
  ) async => AudioEffectSetEnabledResponse();

  @override
  Future<AndroidLoudnessEnhancerSetTargetGainResponse> androidLoudnessEnhancerSetTargetGain(
    AndroidLoudnessEnhancerSetTargetGainRequest request,
  ) async => AndroidLoudnessEnhancerSetTargetGainResponse();

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
    AndroidEqualizerGetParametersRequest request,
  ) async => AndroidEqualizerGetParametersResponse(
    parameters: AndroidEqualizerParametersMessage(minDecibels: 0, maxDecibels: 10, bands: []),
  );

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
    AndroidEqualizerBandSetGainRequest request,
  ) async => AndroidEqualizerBandSetGainResponse();
}
