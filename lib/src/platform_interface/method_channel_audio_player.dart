import 'dart:async';

import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter/services.dart';

/// Prefix shared by every channel name; must match the native implementations.
const _channelPrefix = 'uz.plugin.audio_player';

/// Invokes [method] on [channel] and returns the reply map.
///
/// Every native handler replies with a map, so a `null` reply means the
/// handler is missing or misbehaving. That is reported as a
/// [PlatformException] instead of crashing on a null check.
Future<Map<dynamic, dynamic>> _invoke(MethodChannel channel, String method, Map<dynamic, dynamic> arguments) async {
  final reply = await channel.invokeMethod<Map<dynamic, dynamic>>(method, arguments);
  if (reply == null) {
    throw PlatformException(code: 'null-reply', message: 'The platform returned no reply for "$method".');
  }
  return reply;
}

/// An implementation of [AudioPlayerPlatform] that uses method channels.
class MethodChannelAudioPlayerPlatform extends AudioPlayerPlatform {
  static const _mainChannel = MethodChannel('$_channelPrefix.methods');

  @override
  Future<AudioPlayerInstancePlatform> init(InitRequest request) async {
    await _mainChannel.invokeMethod<void>('init', request.toMap());
    return MethodChannelAudioPlayerInstance(request.id);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async =>
      DisposePlayerResponse.fromMap(await _invoke(_mainChannel, 'disposePlayer', request.toMap()));

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async =>
      DisposeAllPlayersResponse.fromMap(await _invoke(_mainChannel, 'disposeAllPlayers', request.toMap()));
}

/// An implementation of [AudioPlayerInstancePlatform] that uses method channels.
class MethodChannelAudioPlayerInstance extends AudioPlayerInstancePlatform {
  new(super.id)
    : _channel = MethodChannel('$_channelPrefix.methods.$id'),
      _playbackEvents = EventChannel('$_channelPrefix.events.$id')
          .receiveBroadcastStream()
          .cast<Map<dynamic, dynamic>>()
          .map(PlaybackEventMessage.fromMap),
      _playerData = EventChannel('$_channelPrefix.data.$id')
          .receiveBroadcastStream()
          .cast<Map<dynamic, dynamic>>()
          .map(PlayerDataMessage.fromMap);

  final MethodChannel _channel;

  // The event streams are created once per player. Each is a broadcast stream
  // that only attaches to the native side while it has listeners.
  final Stream<PlaybackEventMessage> _playbackEvents;
  final Stream<PlayerDataMessage> _playerData;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _playbackEvents;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _playerData;

  Future<Map<dynamic, dynamic>> _call(String method, Map<dynamic, dynamic> arguments) =>
      _invoke(_channel, method, arguments);

  @override
  Future<LoadResponse> load(LoadRequest request) async => LoadResponse.fromMap(await _call('load', request.toMap()));

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse.fromMap(await _call('play', request.toMap()));

  @override
  Future<PauseResponse> pause(PauseRequest request) async =>
      PauseResponse.fromMap(await _call('pause', request.toMap()));

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse.fromMap(await _call('setVolume', request.toMap()));

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse.fromMap(await _call('setSpeed', request.toMap()));

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse.fromMap(await _call('setPitch', request.toMap()));

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse.fromMap(await _call('setSkipSilence', request.toMap()));

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse.fromMap(await _call('setLoopMode', request.toMap()));

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async =>
      SetShuffleModeResponse.fromMap(await _call('setShuffleMode', request.toMap()));

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async =>
      SetShuffleOrderResponse.fromMap(await _call('setShuffleOrder', request.toMap()));

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse.fromMap(
    await _call('setAutomaticallyWaitsToMinimizeStalling', request.toMap()),
  );

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) async => SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse.fromMap(
    await _call('setCanUseNetworkResourcesForLiveStreamingWhilePaused', request.toMap()),
  );

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse.fromMap(await _call('setPreferredPeakBitRate', request.toMap()));

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse.fromMap(await _call('setAllowsExternalPlayback', request.toMap()));

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse.fromMap(await _call('seek', request.toMap()));

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) async =>
      SetAndroidAudioAttributesResponse.fromMap(await _call('setAndroidAudioAttributes', request.toMap()));

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async =>
      DisposeResponse.fromMap(await _call('dispose', request.toMap()));

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(ConcatenatingInsertAllRequest request) async =>
      ConcatenatingInsertAllResponse.fromMap(await _call('concatenatingInsertAll', request.toMap()));

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(ConcatenatingRemoveRangeRequest request) async =>
      ConcatenatingRemoveRangeResponse.fromMap(await _call('concatenatingRemoveRange', request.toMap()));

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(ConcatenatingMoveRequest request) async =>
      ConcatenatingMoveResponse.fromMap(await _call('concatenatingMove', request.toMap()));

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) async =>
      AudioEffectSetEnabledResponse.fromMap(await _call('audioEffectSetEnabled', request.toMap()));

  @override
  Future<AndroidLoudnessEnhancerSetTargetGainResponse> androidLoudnessEnhancerSetTargetGain(
    AndroidLoudnessEnhancerSetTargetGainRequest request,
  ) async => AndroidLoudnessEnhancerSetTargetGainResponse.fromMap(
    await _call('androidLoudnessEnhancerSetTargetGain', request.toMap()),
  );

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
    AndroidEqualizerGetParametersRequest request,
  ) async =>
      AndroidEqualizerGetParametersResponse.fromMap(await _call('androidEqualizerGetParameters', request.toMap()));

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
    AndroidEqualizerBandSetGainRequest request,
  ) async => AndroidEqualizerBandSetGainResponse.fromMap(await _call('androidEqualizerBandSetGain', request.toMap()));
}
