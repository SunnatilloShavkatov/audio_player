part of 'audio_player_platform_interface.dart';

// Message classes build themselves with static fromMap constructors, which is the wire format.
// Message classes build themselves with static fromMap constructors, and the empty responses have only static members.
// ignore_for_file: prefer_constructors_over_static_methods, avoid_classes_with_only_static_members

/// Information communicated to the platform implementation when setting the
/// audio load configuration options.
class AudioLoadConfigurationMessage {
  const new({
    required this.darwinLoadControl,
    required this.androidLoadControl,
    required this.androidLivePlaybackSpeedControl,
  });
  final DarwinLoadControlMessage? darwinLoadControl;
  final AndroidLoadControlMessage? androidLoadControl;
  final AndroidLivePlaybackSpeedControlMessage? androidLivePlaybackSpeedControl;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'darwinLoadControl': darwinLoadControl?.toMap(),
    'androidLoadControl': androidLoadControl?.toMap(),
    'androidLivePlaybackSpeedControl': androidLivePlaybackSpeedControl?.toMap(),
  };
}

class DarwinLoadControlMessage {
  new({
    required this.automaticallyWaitsToMinimizeStalling,
    required this.preferredForwardBufferDuration,
    required this.canUseNetworkResourcesForLiveStreamingWhilePaused,
    required this.preferredPeakBitRate,
  });

  /// (iOS/macOS) Whether the player will wait for sufficient data to be
  /// buffered before starting playback to avoid the likelihood of stalling.
  final bool automaticallyWaitsToMinimizeStalling;

  /// (iOS/macOS) The duration of audio that should be buffered ahead of the
  /// current position. If not set or `null`, the system will try to set an
  /// appropriate buffer duration.
  final Duration? preferredForwardBufferDuration;

  /// (iOS/macOS) Whether the player can continue downloading while paused to
  /// keep the state up to date with the live stream.
  final bool canUseNetworkResourcesForLiveStreamingWhilePaused;

  /// (iOS/macOS) If specified, limits the download bandwidth in bits per
  /// second.
  final double? preferredPeakBitRate;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'automaticallyWaitsToMinimizeStalling': automaticallyWaitsToMinimizeStalling,
    'preferredForwardBufferDuration': preferredForwardBufferDuration?.inMicroseconds,
    'canUseNetworkResourcesForLiveStreamingWhilePaused': canUseNetworkResourcesForLiveStreamingWhilePaused,
    'preferredPeakBitRate': preferredPeakBitRate,
  };
}

class AndroidLoadControlMessage {
  new({
    required this.minBufferDuration,
    required this.maxBufferDuration,
    required this.bufferForPlaybackDuration,
    required this.bufferForPlaybackAfterRebufferDuration,
    required this.targetBufferBytes,
    required this.prioritizeTimeOverSizeThresholds,
    required this.backBufferDuration,
  });

  /// (Android) The minimum duration of audio that should be buffered ahead of
  /// the current position.
  final Duration minBufferDuration;

  /// (Android) The maximum duration of audio that should be buffered ahead of
  /// the current position.
  final Duration maxBufferDuration;

  /// (Android) The duration of audio that must be buffered before starting
  /// playback after a user action.
  final Duration bufferForPlaybackDuration;

  /// (Android) The duration of audio that must be buffered before starting
  /// playback after a buffer depletion.
  final Duration bufferForPlaybackAfterRebufferDuration;

  /// (Android) The target buffer size in bytes.
  final int? targetBufferBytes;

  /// (Android) Whether to prioritize buffer time constraints over buffer size
  /// constraints.
  final bool prioritizeTimeOverSizeThresholds;

  /// (Android) The back buffer duration.
  final Duration backBufferDuration;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'minBufferDuration': minBufferDuration.inMicroseconds,
    'maxBufferDuration': maxBufferDuration.inMicroseconds,
    'bufferForPlaybackDuration': bufferForPlaybackDuration.inMicroseconds,
    'bufferForPlaybackAfterRebufferDuration': bufferForPlaybackAfterRebufferDuration.inMicroseconds,
    'targetBufferBytes': targetBufferBytes,
    'prioritizeTimeOverSizeThresholds': prioritizeTimeOverSizeThresholds,
    'backBufferDuration': backBufferDuration.inMicroseconds,
  };
}

class AndroidLivePlaybackSpeedControlMessage {
  new({
    required this.fallbackMinPlaybackSpeed,
    required this.fallbackMaxPlaybackSpeed,
    required this.minUpdateInterval,
    required this.proportionalControlFactor,
    required this.maxLiveOffsetErrorForUnitSpeed,
    required this.targetLiveOffsetIncrementOnRebuffer,
    required this.minPossibleLiveOffsetSmoothingFactor,
  });

  /// (Android) The minimum playback speed to use when adjusting playback speed
  /// to approach the target live offset, if none is defined by the media.
  final double fallbackMinPlaybackSpeed;

  /// (Android) The maximum playback speed to use when adjusting playback speed
  /// to approach the target live offset, if none is defined by the media.
  final double fallbackMaxPlaybackSpeed;

  /// (Android) The minimum interval between playback speed changes on a live
  /// stream.
  final Duration minUpdateInterval;

  /// (Android) The proportional control factor used to adjust playback speed on
  /// a live stream. The adjusted speed is calculated as: `1.0 +
  /// proportionalControlFactor * (currentLiveOffsetSec - targetLiveOffsetSec)`.
  final double proportionalControlFactor;

  /// (Android) The maximum difference between the current live offset and the
  /// target live offset within which the speed 1.0 is used.
  final Duration maxLiveOffsetErrorForUnitSpeed;

  /// (Android) The increment applied to the target live offset whenever the
  /// player rebuffers.
  final Duration targetLiveOffsetIncrementOnRebuffer;

  /// (Android) The factor for smoothing the minimum possible live offset
  /// achievable during playback.
  final double minPossibleLiveOffsetSmoothingFactor;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'fallbackMinPlaybackSpeed': fallbackMinPlaybackSpeed,
    'fallbackMaxPlaybackSpeed': fallbackMaxPlaybackSpeed,
    'minUpdateInterval': minUpdateInterval.inMicroseconds,
    'proportionalControlFactor': proportionalControlFactor,
    'maxLiveOffsetErrorForUnitSpeed': maxLiveOffsetErrorForUnitSpeed.inMicroseconds,
    'targetLiveOffsetIncrementOnRebuffer': targetLiveOffsetIncrementOnRebuffer.inMicroseconds,
    'minPossibleLiveOffsetSmoothingFactor': minPossibleLiveOffsetSmoothingFactor,
  };
}

/// The loop mode communicated to the platform implementation.
enum AndroidAudioOffloadModeMessage { disabled, enabled }

/// Information communicated to the platform implementation when setting the
/// audio offload preferences.
class AndroidAudioOffloadPreferencesMessage {
  new({
    required this.audioOffloadMode,
    required this.isGaplessSupportRequired,
    required this.isSpeedChangeSupportRequired,
  });
  final AndroidAudioOffloadModeMessage audioOffloadMode;
  final bool isGaplessSupportRequired;
  final bool isSpeedChangeSupportRequired;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'audioOffloadMode': audioOffloadMode.index,
    'isGaplessSupportRequired': isGaplessSupportRequired,
    'isSpeedChangeSupportRequired': isSpeedChangeSupportRequired,
  };
}

/// Progressive audio source options to be communicated with the platform
/// implementation.
class ProgressiveAudioSourceOptionsMessage {
  const new({this.androidExtractorOptions, this.darwinAssetOptions});
  final AndroidExtractorOptionsMessage? androidExtractorOptions;
  final DarwinAssetOptionsMessage? darwinAssetOptions;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'androidExtractorOptions': androidExtractorOptions?.toMap(),
    'darwinAssetOptions': darwinAssetOptions?.toMap(),
  };
}

/// Options for loading audio assets on iOS/macOS to be communicated with the
/// platform implementation.
class DarwinAssetOptionsMessage {
  const new({required this.preferPreciseDurationAndTiming});
  final bool preferPreciseDurationAndTiming;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{'preferPreciseDurationAndTiming': preferPreciseDurationAndTiming};
}

/// Options for extracting media files on Android to be communicated with the
/// platform implementation.
class AndroidExtractorOptionsMessage {
  const new({
    required this.constantBitrateSeekingEnabled,
    required this.constantBitrateSeekingAlwaysEnabled,
    required this.mp3Flags,
  });
  final bool constantBitrateSeekingEnabled;
  final bool constantBitrateSeekingAlwaysEnabled;
  final int mp3Flags;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'constantBitrateSeekingEnabled': constantBitrateSeekingEnabled,
    'constantBitrateSeekingAlwaysEnabled': constantBitrateSeekingAlwaysEnabled,
    'mp3Flags': mp3Flags,
  };
}

/// Information about an audio source to be communicated with the platform
/// implementation.
abstract class AudioSourceMessage {
  new({required this.id});
  final String id;

  Map<dynamic, dynamic> toMap();
}

/// Information about an indexed audio source to be communicated with the
/// platform implementation.
abstract class IndexedAudioSourceMessage extends AudioSourceMessage {
  new({required super.id, this.tag});

  /// Since the tag type is unknown, this can only be used by platform
  /// implementations that pass by reference.
  final dynamic tag;
}

/// Information about a URI audio source to be communicated with the platform
/// implementation.
abstract class UriAudioSourceMessage extends IndexedAudioSourceMessage {
  new({required super.id, required this.uri, this.headers, super.tag});
  final String uri;
  final Map<String, String>? headers;
}

/// Information about a progressive audio source to be communicated with the
/// platform implementation.
class ProgressiveAudioSourceMessage extends UriAudioSourceMessage {
  new({required super.id, required super.uri, super.headers, super.tag, this.options});
  final ProgressiveAudioSourceOptionsMessage? options;

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'type': 'progressive',
    'id': id,
    'uri': uri,
    'headers': headers,
    'options': options?.toMap(),
  };
}

/// Information about a DASH audio source to be communicated with the platform
/// implementation.
class DashAudioSourceMessage extends UriAudioSourceMessage {
  new({required super.id, required super.uri, super.headers, super.tag});

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{'type': 'dash', 'id': id, 'uri': uri, 'headers': headers};
}

/// Information about a HLS audio source to be communicated with the platform
/// implementation.
class HlsAudioSourceMessage extends UriAudioSourceMessage {
  new({required super.id, required super.uri, super.headers, super.tag});

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{'type': 'hls', 'id': id, 'uri': uri, 'headers': headers};
}

/// Information about a silence audio source to be communicated with the
/// platform implementation.
class SilenceAudioSourceMessage extends IndexedAudioSourceMessage {
  new({required super.id, required this.duration});
  final Duration duration;

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{'type': 'silence', 'id': id, 'duration': duration.inMicroseconds};
}

/// Information about a concatenating audio source to be communicated with the
/// platform implementation.
class ConcatenatingAudioSourceMessage extends AudioSourceMessage {
  new({required super.id, required this.children, required this.useLazyPreparation, required this.shuffleOrder});
  final List<AudioSourceMessage> children;
  final bool useLazyPreparation;
  final List<int> shuffleOrder;

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'type': 'concatenating',
    'id': id,
    'children': children.map((child) => child.toMap()).toList(),
    'useLazyPreparation': useLazyPreparation,
    'shuffleOrder': shuffleOrder,
  };
}

/// Information about a clipping audio source to be communicated with the
/// platform implementation.
class ClippingAudioSourceMessage extends IndexedAudioSourceMessage {
  new({required super.id, required this.child, this.start, this.end, super.tag});
  final UriAudioSourceMessage child;
  final Duration? start;
  final Duration? end;

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'type': 'clipping',
    'id': id,
    'child': child.toMap(),
    'start': start?.inMicroseconds,
    'end': end?.inMicroseconds,
  };
}

/// Information communicated to the platform implementation when setting the
/// enabled status of an audio effect.
class AudioEffectSetEnabledRequest {
  new({required this.type, required this.enabled});
  final String type;
  final bool enabled;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{'type': type, 'enabled': enabled};
}

/// Information returned by the platform implementation after setting the
/// enabled status of an audio effect.
class AudioEffectSetEnabledResponse {
  static AudioEffectSetEnabledResponse fromMap(Map<dynamic, dynamic> map) => AudioEffectSetEnabledResponse();
}

/// Information communicated to the platform implementation when setting the
/// target gain on the loudness enhancer audio effect.
class AndroidLoudnessEnhancerSetTargetGainRequest {
  new({required this.targetGain});

  /// The target gain in decibels.
  final double targetGain;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{'targetGain': targetGain};
}

/// Information returned by the platform implementation after setting the target
/// gain on the loudness enhancer audio effect.
class AndroidLoudnessEnhancerSetTargetGainResponse {
  static AndroidLoudnessEnhancerSetTargetGainResponse fromMap(Map<dynamic, dynamic> map) =>
      AndroidLoudnessEnhancerSetTargetGainResponse();
}

/// Information communicated to the platform implementation when requesting the
/// equalizer parameters.
class AndroidEqualizerGetParametersRequest {
  new();

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

/// Information communicated to the platform implementation after requesting the
/// equalizer parameters.
class AndroidEqualizerGetParametersResponse {
  new({required this.parameters});
  final AndroidEqualizerParametersMessage parameters;

  static AndroidEqualizerGetParametersResponse fromMap(Map<dynamic, dynamic> map) =>
      AndroidEqualizerGetParametersResponse(
        parameters: AndroidEqualizerParametersMessage.fromMap(map['parameters'] as Map<dynamic, dynamic>),
      );
}

/// Information communicated to the platform implementation when setting the
/// gain for an equalizer band.
class AndroidEqualizerBandSetGainRequest {
  new({required this.bandIndex, required this.gain});
  final int bandIndex;
  final double gain;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{'bandIndex': bandIndex, 'gain': gain};
}

/// Information returned by the platform implementation after setting the gain
/// for an equalizer band.
class AndroidEqualizerBandSetGainResponse {
  new();

  static AndroidEqualizerBandSetGainResponse fromMap(Map<dynamic, dynamic> map) =>
      AndroidEqualizerBandSetGainResponse();
}

/// Information about an audio effect to be communicated with the platform
/// implementation.
abstract class AudioEffectMessage {
  new({required this.enabled});
  final bool enabled;

  Map<dynamic, dynamic> toMap();
}

/// Information about a loudness enhancer to be communicated with the platform
/// implementation.
class AndroidLoudnessEnhancerMessage extends AudioEffectMessage {
  new({required super.enabled, required this.targetGain});
  final double targetGain;

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'type': 'AndroidLoudnessEnhancer',
    'enabled': enabled,
    'targetGain': targetGain,
  };
}

/// Information about an equalizer band to be communicated with the platform
/// implementation.
class AndroidEqualizerBandMessage {
  new({
    required this.index,
    required this.lowerFrequency,
    required this.upperFrequency,
    required this.centerFrequency,
    required this.gain,
  });

  /// A zero-based index of the position of this band within its [AndroidEqualizer].
  final int index;

  /// The lower frequency of this band in hertz.
  final double lowerFrequency;

  /// The upper frequency of this band in hertz.
  final double upperFrequency;

  /// The center frequency of this band in hertz.
  final double centerFrequency;

  /// The gain for this band in decibels.
  final double gain;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'index': index,
    'lowerFrequency': lowerFrequency,
    'upperFrequency': upperFrequency,
    'centerFrequency': centerFrequency,
    'gain': gain,
  };

  static AndroidEqualizerBandMessage fromMap(Map<dynamic, dynamic> map) => AndroidEqualizerBandMessage(
    index: map['index'] as int,
    lowerFrequency: (map['lowerFrequency'] as num).toDouble(),
    upperFrequency: (map['upperFrequency'] as num).toDouble(),
    centerFrequency: (map['centerFrequency'] as num).toDouble(),
    gain: (map['gain'] as num).toDouble(),
  );
}

/// Information about the equalizer parameters to be communicated with the
/// platform implementation.
class AndroidEqualizerParametersMessage {
  new({required this.minDecibels, required this.maxDecibels, required this.bands});
  final double minDecibels;
  final double maxDecibels;
  final List<AndroidEqualizerBandMessage> bands;

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'minDecibels': minDecibels,
    'maxDecibels': maxDecibels,
    'bands': bands.map((band) => band.toMap()).toList(),
  };

  static AndroidEqualizerParametersMessage fromMap(Map<dynamic, dynamic> map) => AndroidEqualizerParametersMessage(
    minDecibels: (map['minDecibels'] as num).toDouble(),
    maxDecibels: (map['maxDecibels'] as num).toDouble(),
    bands: (map['bands'] as List<dynamic>)
        .map((bandMap) => AndroidEqualizerBandMessage.fromMap(bandMap as Map<dynamic, dynamic>))
        .toList(),
  );
}

/// Information about the equalizer to be communicated with the platform
/// implementation.
class AndroidEqualizerMessage extends AudioEffectMessage {
  new({required super.enabled, required this.parameters});
  final AndroidEqualizerParametersMessage? parameters;

  @override
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
    'type': 'AndroidEqualizer',
    'enabled': enabled,
    'parameters': parameters?.toMap(),
  };
}
