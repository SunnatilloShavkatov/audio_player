part of 'audio_player.dart';

class ProgressiveAudioSourceOptions {
  const new({this.androidExtractorOptions, this.darwinAssetOptions});
  final AndroidExtractorOptions? androidExtractorOptions;
  final DarwinAssetOptions? darwinAssetOptions;

  ProgressiveAudioSourceOptionsMessage _toMessage() => ProgressiveAudioSourceOptionsMessage(
    androidExtractorOptions: androidExtractorOptions?._toMessage(),
    darwinAssetOptions: darwinAssetOptions?._toMessage(),
  );
}

class DarwinAssetOptions {
  const new({this.preferPreciseDurationAndTiming = false});
  final bool preferPreciseDurationAndTiming;

  DarwinAssetOptionsMessage _toMessage() =>
      DarwinAssetOptionsMessage(preferPreciseDurationAndTiming: preferPreciseDurationAndTiming);
}

class AndroidExtractorOptions {
  const new({
    this.constantBitrateSeekingEnabled = true,
    this.constantBitrateSeekingAlwaysEnabled = false,
    this.mp3Flags = 0,
  });
  static const flagMp3EnableIndexSeeking = 1 << 2;
  static const flagMp3DisableId3Metadata = 1 << 3;

  final bool constantBitrateSeekingEnabled;
  final bool constantBitrateSeekingAlwaysEnabled;
  final int mp3Flags;

  AndroidExtractorOptionsMessage _toMessage() => AndroidExtractorOptionsMessage(
    constantBitrateSeekingEnabled: constantBitrateSeekingEnabled,
    constantBitrateSeekingAlwaysEnabled: constantBitrateSeekingAlwaysEnabled,
    mp3Flags: mp3Flags,
  );
}

/// Possible values that can be passed to [AudioPlayer.setWebCrossOrigin].
enum WebCrossOrigin { anonymous, useCredentials }
