// Platform interface for the native audio player. The request/response
// messages are plain data holders with static `fromMap`s.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_player/audio_player.dart' show AndroidEqualizer;
import 'package:audio_player/src/platform_interface/audio_player_android.dart';
import 'package:audio_player/src/platform_interface/audio_player_darwin.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

part 'audio_player_platform_requests.dart';
part 'audio_player_platform_sources.dart';

/// The interface that implementations of audio_player must implement.
///
/// Platform implementations should extend this class rather than implement it
/// as `audio_player` does not consider newly added methods to be breaking
/// changes. Extending this class (using `extends`) ensures that the subclass
/// will get the default implementation, while platform implementations that
/// `implements` this interface will be broken by newly added
/// [AudioPlayerPlatform] methods.
abstract class AudioPlayerPlatform extends PlatformInterface {
  /// Constructs a AudioPlayerPlatform.
  new() : super(token: _token);

  static final Object _token = Object();

  static AudioPlayerPlatform _instance = Platform.isAndroid
      ? AndroidAudioPlayerPlatform()
      : DarwinAudioPlayerPlatform();

  /// The default instance of [AudioPlayerPlatform] to use.
  ///
  /// Defaults to [AndroidAudioPlayerPlatform] on Android and [DarwinAudioPlayerPlatform] elsewhere.
  static AudioPlayerPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [AudioPlayerPlatform] when they register themselves.
  static set instance(AudioPlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Creates a new platform player and returns a nested platform interface for
  /// communicating with that player.
  Future<AudioPlayerInstancePlatform> init(InitRequest request) {
    throw UnimplementedError('init() has not been implemented.');
  }

  /// Disposes of a platform player.
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) {
    throw UnimplementedError('disposePlayer() has not been implemented.');
  }

  /// Disposes of all platform players.
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) {
    throw UnimplementedError('disposeAllPlayers() has not been implemented.');
  }
}

/// A nested platform interface for communicating with a particular player
/// instance.
///
/// Platform implementations should extend this class rather than implement it
/// as `audio_player` does not consider newly added methods to be breaking
/// changes. Extending this class (using `extends`) ensures that the subclass
/// will get the default implementation, while platform implementations that
/// `implements` this interface will be broken by newly added
/// [AudioPlayerInstancePlatform] methods.
abstract class AudioPlayerInstancePlatform {
  new(this.id);
  final String id;

  /// A broadcast stream of playback events.
  Stream<PlaybackEventMessage> get playbackEventMessageStream {
    throw UnimplementedError('playbackEventMessageStream has not been implemented.');
  }

  /// A broadcast stream of data updates.
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream<PlayerDataMessage>.empty();

  /// Loads an audio source.
  Future<LoadResponse> load(LoadRequest request) {
    throw UnimplementedError('load() has not been implemented.');
  }

  /// Plays the current audio source at the current index and position.
  Future<PlayResponse> play(PlayRequest request) {
    throw UnimplementedError('play() has not been implemented.');
  }

  /// Pauses playback.
  Future<PauseResponse> pause(PauseRequest request) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Changes the volume.
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  /// Changes the playback speed.
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) {
    throw UnimplementedError('setSpeed() has not been implemented.');
  }

  /// Changes the pitch.
  Future<SetPitchResponse> setPitch(SetPitchRequest request) {
    throw UnimplementedError('setPitch() has not been implemented.');
  }

  /// Sets skipSilence to true/false.
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) {
    throw UnimplementedError('setSkipSilence() has not been implemented.');
  }

  /// Sets the loop mode.
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) {
    throw UnimplementedError('setLoopMode() has not been implemented.');
  }

  /// Sets the shuffle mode.
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) {
    throw UnimplementedError('setShuffleMode() has not been implemented.');
  }

  /// Sets the shuffle order.
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) {
    throw UnimplementedError('setShuffleOrder() has not been implemented.');
  }

  /// On iOS and macOS, sets the automaticallyWaitsToMinimizeStalling option,
  /// and does nothing on other platforms.
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) {
    throw UnimplementedError('setAutomaticallyWaitsToMinimizeStalling() has not been implemented.');
  }

  /// On iOS and macOS, sets the
  /// canUseNetworkResourcesForLiveStreamingWhilePaused option, and does nothing
  /// on other platforms.
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) {
    throw UnimplementedError('setCanUseNetworkResourcesForLiveStreamingWhilePaused() has not been implemented.');
  }

  /// On iOS and macOS, sets the preferredPeakBitRate option, and does nothing
  /// on other platforms.
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(SetPreferredPeakBitRateRequest request) {
    throw UnimplementedError('setPreferredPeakBitRate() has not been implemented.');
  }

  /// On iOS and macOS, sets the allowsExternalPlayback option, and does nothing
  /// on other platforms.
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(SetAllowsExternalPlaybackRequest request) {
    throw UnimplementedError('setAllowsExternalPlayback() has not been implemented.');
  }

  /// Seeks to the given index and position.
  Future<SeekResponse> seek(SeekRequest request) {
    throw UnimplementedError('seek() has not been implemented.');
  }

  /// On Android, sets the audio attributes, and does nothing on other
  /// platforms.
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) {
    throw UnimplementedError('setAndroidAudioAttributes() has not been implemented.');
  }

  /// This method has been superseded by [AudioPlayerPlatform.disposePlayer].
  /// For backward compatibility, this method will still be called as a
  /// fallback if [AudioPlayerPlatform.disposePlayer] is not implemented.
  Future<DisposeResponse> dispose(DisposeRequest request) {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  /// Inserts audio sources into the given concatenating audio source.
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(ConcatenatingInsertAllRequest request) {
    throw UnimplementedError('concatenatingInsertAll() has not been implemented.');
  }

  /// Removes audio sources from the given concatenating audio source.
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(ConcatenatingRemoveRangeRequest request) {
    throw UnimplementedError('concatenatingRemoveRange() has not been implemented.');
  }

  /// Moves an audio source within a concatenating audio source.
  Future<ConcatenatingMoveResponse> concatenatingMove(ConcatenatingMoveRequest request) {
    throw UnimplementedError('concatenatingMove() has not been implemented.');
  }

  /// Changes the enabled status of an audio effect.
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) {
    throw UnimplementedError('audioEffectSetEnabled() has not been implemented.');
  }

  /// Sets the target gain on the Android loudness enhancer.
  Future<AndroidLoudnessEnhancerSetTargetGainResponse> androidLoudnessEnhancerSetTargetGain(
    AndroidLoudnessEnhancerSetTargetGainRequest request,
  ) {
    throw UnimplementedError('androidLoudnessEnhancerSetTargetGain() has not been implemented.');
  }

  /// Gets the Android equalizer parameters.
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
    AndroidEqualizerGetParametersRequest request,
  ) {
    throw UnimplementedError('androidEqualizerGetParameters() has not been implemented.');
  }

  /// Sets the gain for an Android equalizer band.
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(AndroidEqualizerBandSetGainRequest request) {
    throw UnimplementedError('androidEqualizerBandSetGain() has not been implemented.');
  }
}
