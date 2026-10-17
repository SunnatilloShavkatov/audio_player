part of 'audio_player.dart';

/// Configuration options to use when loading audio from a source.
class AudioLoadConfiguration {
  const new({this.darwinLoadControl, this.androidLoadControl, this.androidLivePlaybackSpeedControl});

  /// Buffering and loading options for iOS/macOS.
  final DarwinLoadControl? darwinLoadControl;

  /// Buffering and loading options for Android.
  final AndroidLoadControl? androidLoadControl;

  /// Speed control for live streams on Android.
  final AndroidLivePlaybackSpeedControl? androidLivePlaybackSpeedControl;

  AudioLoadConfigurationMessage _toMessage() => AudioLoadConfigurationMessage(
    darwinLoadControl: darwinLoadControl?._toMessage(),
    androidLoadControl: androidLoadControl?._toMessage(),
    androidLivePlaybackSpeedControl: androidLivePlaybackSpeedControl?._toMessage(),
  );
}

/// Buffering and loading options for iOS/macOS.
class DarwinLoadControl {
  const new({
    this.automaticallyWaitsToMinimizeStalling = true,
    this.preferredForwardBufferDuration,
    this.canUseNetworkResourcesForLiveStreamingWhilePaused = false,
    this.preferredPeakBitRate,
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

  DarwinLoadControlMessage _toMessage() => DarwinLoadControlMessage(
    automaticallyWaitsToMinimizeStalling: automaticallyWaitsToMinimizeStalling,
    preferredForwardBufferDuration: preferredForwardBufferDuration,
    canUseNetworkResourcesForLiveStreamingWhilePaused: canUseNetworkResourcesForLiveStreamingWhilePaused,
    preferredPeakBitRate: preferredPeakBitRate,
  );
}

/// Buffering and loading options for Android.
class AndroidLoadControl {
  const new({
    this.minBufferDuration = const Duration(seconds: 50),
    this.maxBufferDuration = const Duration(seconds: 50),
    this.bufferForPlaybackDuration = const Duration(milliseconds: 2500),
    this.bufferForPlaybackAfterRebufferDuration = const Duration(seconds: 5),
    this.targetBufferBytes,
    this.prioritizeTimeOverSizeThresholds = false,
    this.backBufferDuration = Duration.zero,
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

  AndroidLoadControlMessage _toMessage() => AndroidLoadControlMessage(
    minBufferDuration: minBufferDuration,
    maxBufferDuration: maxBufferDuration,
    bufferForPlaybackDuration: bufferForPlaybackDuration,
    bufferForPlaybackAfterRebufferDuration: bufferForPlaybackAfterRebufferDuration,
    targetBufferBytes: targetBufferBytes,
    prioritizeTimeOverSizeThresholds: prioritizeTimeOverSizeThresholds,
    backBufferDuration: backBufferDuration,
  );
}

/// Speed control for live streams on Android.
class AndroidLivePlaybackSpeedControl {
  const new({
    this.fallbackMinPlaybackSpeed = 0.97,
    this.fallbackMaxPlaybackSpeed = 1.03,
    this.minUpdateInterval = const Duration(seconds: 1),
    this.proportionalControlFactor = 1.0,
    this.maxLiveOffsetErrorForUnitSpeed = const Duration(milliseconds: 20),
    this.targetLiveOffsetIncrementOnRebuffer = const Duration(milliseconds: 500),
    this.minPossibleLiveOffsetSmoothingFactor = 0.999,
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

  AndroidLivePlaybackSpeedControlMessage _toMessage() => AndroidLivePlaybackSpeedControlMessage(
    fallbackMinPlaybackSpeed: fallbackMinPlaybackSpeed,
    fallbackMaxPlaybackSpeed: fallbackMaxPlaybackSpeed,
    minUpdateInterval: minUpdateInterval,
    proportionalControlFactor: proportionalControlFactor,
    maxLiveOffsetErrorForUnitSpeed: maxLiveOffsetErrorForUnitSpeed,
    targetLiveOffsetIncrementOnRebuffer: targetLiveOffsetIncrementOnRebuffer,
    minPossibleLiveOffsetSmoothingFactor: minPossibleLiveOffsetSmoothingFactor,
  );
}

/// Audio offload modes for Android.
enum AndroidAudioOffloadMode { disabled, enabled }

/// Audio offload preferences for Android.
///
/// IMPORTANT: activation of audio offload depends on a negotiation between
/// ExoPlayer and the device to determine whether offload can be supported for a
/// given format and with given constraints (gapless, speed change). However,
/// several instances have been reported where the device incorrectly confirms
/// support for audio offload when it doesn't, and this can result in buggy
/// audio playback. Therefore, it is advised that you programmatically enable
/// audio offload only on device/OS combinations that you have tested and
/// verified to work.
class AndroidAudioOffloadPreferences {
  const new({
    this.audioOffloadMode = AndroidAudioOffloadMode.disabled,
    this.isGaplessSupportRequired = false,
    this.isSpeedChangeSupportRequired = false,
  });

  /// The preferred audio offload mode.
  final AndroidAudioOffloadMode audioOffloadMode;

  /// Constrains enablement of audio offload to happen only if the device
  /// can fulfill any gapless transitions that might exist in the playlist
  /// during offload.
  final bool isGaplessSupportRequired;

  /// Constrains enablement of audio offload to happen only if the device
  /// can fulfill any speed change request during offload.
  final bool isSpeedChangeSupportRequired;

  AndroidAudioOffloadPreferencesMessage _toMessage() => AndroidAudioOffloadPreferencesMessage(
    audioOffloadMode: AndroidAudioOffloadModeMessage.values[audioOffloadMode.index],
    isGaplessSupportRequired: isGaplessSupportRequired,
    isSpeedChangeSupportRequired: isSpeedChangeSupportRequired,
  );
}
