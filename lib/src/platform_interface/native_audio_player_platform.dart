import 'dart:async';
import 'dart:convert';

import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter/services.dart';

/// The way [NativeAudioPlayerPlatform] reaches the native players: JSON requests and replies, plus listener
/// callbacks for events. Android (JNI) and Darwin (Objective-C runtime) each implement [send] and [listen].
abstract class NativeAudioPlayerTransport {
  final _playbackEvents = <String, StreamController<PlaybackEventMessage>>{};
  final _playerData = <String, StreamController<PlayerDataMessage>>{};
  bool _listening = false;

  /// Sends the JSON [request] of [method] (to player [playerId], or to the plugin when null) and returns the JSON
  /// reply. Native failures complete with a [PlatformException].
  Future<String> send(String? playerId, String method, String request);

  /// Registers the native event callbacks, which must call [onPlaybackEvent], [onPlayerData] and
  /// [onPlaybackError].
  void listen();

  /// Makes sure the native side delivers events, once.
  void ensureListening() {
    if (_listening) {
      return;
    }
    _listening = true;
    listen();
  }

  /// Sends a request and decodes the reply map.
  Future<Map<dynamic, dynamic>> invoke(String? playerId, String method, Map<dynamic, dynamic> arguments) async {
    final reply = await send(playerId, method, jsonEncode(arguments));
    final Object? decoded;
    try {
      decoded = jsonDecode(reply);
    } on FormatException {
      throw PlatformException(code: 'bad-reply', message: 'The platform sent an unreadable reply for "$method".');
    }
    if (decoded is! Map<dynamic, dynamic>) {
      throw PlatformException(code: 'null-reply', message: 'The platform returned no reply for "$method".');
    }
    return decoded;
  }

  /// Starts routing the events of player [id].
  void attach(String id) {
    _playbackEvents.putIfAbsent(id, StreamController<PlaybackEventMessage>.broadcast);
    _playerData.putIfAbsent(id, StreamController<PlayerDataMessage>.broadcast);
  }

  /// Stops routing the events of player [id] and ends its streams.
  void detach(String id) {
    unawaited(_playbackEvents.remove(id)?.close());
    unawaited(_playerData.remove(id)?.close());
  }

  /// [detach]es every player.
  void detachAll() {
    <String>{..._playbackEvents.keys, ..._playerData.keys}.toList().forEach(detach);
  }

  Stream<PlaybackEventMessage> playbackEvents(String id) =>
      (_playbackEvents[id] ??= StreamController.broadcast()).stream;

  Stream<PlayerDataMessage> playerData(String id) => (_playerData[id] ??= StreamController.broadcast()).stream;

  /// A playback event arrived from native. A malformed one becomes a stream error, not a throw into the callback.
  void onPlaybackEvent(String id, String json) {
    try {
      _playbackEvents[id]?.add(PlaybackEventMessage.fromMap(jsonDecode(json) as Map<dynamic, dynamic>));
    } on Object catch (e, st) {
      _playbackEvents[id]?.addError(e, st);
    }
  }

  /// A data update arrived from native.
  void onPlayerData(String id, String json) {
    try {
      _playerData[id]?.add(PlayerDataMessage.fromMap(jsonDecode(json) as Map<dynamic, dynamic>));
    } on Object catch (e, st) {
      _playerData[id]?.addError(e, st);
    }
  }

  /// A playback error arrived from native; it is reported on the playback event stream.
  void onPlaybackError(String id, String code, String? message, String? details) {
    _playbackEvents[id]?.addError(platformException(code, message, details));
  }

  /// Builds the [PlatformException] for a native error; `details` that are JSON maps or lists are decoded.
  static PlatformException platformException(String code, String? message, String? details) {
    Object? decoded = details;
    if (details != null && (details.startsWith('{') || details.startsWith('['))) {
      try {
        decoded = jsonDecode(details);
      } on FormatException {
        decoded = details;
      }
    }
    return PlatformException(code: code, message: message, details: decoded);
  }
}

/// An [AudioPlayerPlatform] over a [NativeAudioPlayerTransport]: no method channels, the same messages as JSON.
class NativeAudioPlayerPlatform extends AudioPlayerPlatform {
  new(this.transport);

  /// How the native players are reached.
  final NativeAudioPlayerTransport transport;

  @override
  Future<AudioPlayerInstancePlatform> init(InitRequest request) async {
    transport
      ..ensureListening()
      ..attach(request.id);
    try {
      await transport.invoke(null, 'init', request.toMap());
    } on Object {
      transport.detach(request.id);
      rethrow;
    }
    return NativeAudioPlayerInstance(request.id, transport);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    final reply = await transport.invoke(null, 'disposePlayer', request.toMap());
    transport.detach(request.id);
    return DisposePlayerResponse.fromMap(reply);
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    transport.ensureListening();
    final reply = await transport.invoke(null, 'disposeAllPlayers', request.toMap());
    transport.detachAll();
    return DisposeAllPlayersResponse.fromMap(reply);
  }
}

/// An [AudioPlayerInstancePlatform] over a [NativeAudioPlayerTransport].
class NativeAudioPlayerInstance extends AudioPlayerInstancePlatform {
  new(super.id, this._transport);

  final NativeAudioPlayerTransport _transport;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _transport.playbackEvents(id);

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _transport.playerData(id);

  Future<Map<dynamic, dynamic>> _call(String method, Map<dynamic, dynamic> arguments) =>
      _transport.invoke(id, method, arguments);

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
