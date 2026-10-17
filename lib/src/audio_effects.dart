part of 'audio_player.dart';

/// The pipeline of audio effects to be applied to an [AudioPlayer].
///
/// Audio effects are currently supported on Android only. On iOS and macOS the
/// effects keep their settings but do not change the audio.
class AudioPipeline {
  new({List<AndroidAudioEffect>? androidAudioEffects})
    : assert(
        androidAudioEffects == null || androidAudioEffects.toSet().length == androidAudioEffects.length,
        'androidAudioEffects must not contain duplicates.',
      ),
      androidAudioEffects = androidAudioEffects ?? const [];
  final List<AndroidAudioEffect> androidAudioEffects;

  /// The effects that the current platform applies.
  List<AudioEffect> get _platformAudioEffects => _isAndroid() ? androidAudioEffects : const [];

  void _setup(AudioPlayer player) {
    for (final effect in androidAudioEffects) {
      effect._setup(player);
    }
  }
}

/// Subclasses of [AudioEffect] can be inserted into an [AudioPipeline] to
/// modify the audio signal outputted by an [AudioPlayer]. The same audio effect
/// instance cannot be set on multiple players at the same time.
///
/// An [AudioEffect] is disabled by default. For an [AudioEffect] to take
/// effect, in addition to being part of an [AudioPipeline] attached to an
/// [AudioPlayer] you must also enable the effect via [setEnabled].
abstract class AudioEffect {
  new();

  AudioPlayer? _player;
  final _enabledSubject = BehaviorSubject.seeded(false);

  /// Called when an [AudioEffect] is attached to an [AudioPlayer].
  void _setup(AudioPlayer player) {
    assert(_player == null, 'An AudioEffect cannot be attached to more than one AudioPlayer.');
    _player = player;
  }

  /// Called when [_player] is connected to the platform.
  Future<void> _activate(AudioPlayerInstancePlatform platform) async {}

  /// Whether the effect is enabled. When `true`, and if the effect is part
  /// of an [AudioPipeline] attached to an [AudioPlayer], the effect will modify
  /// the audio player's output. When `false`, the audio pipeline will still
  /// reserve platform resources for the effect but the effect will be bypassed.
  bool get enabled => _enabledSubject.nullableValue!;

  /// A stream of the current [enabled] value.
  Stream<bool> get enabledStream => _enabledSubject.stream;

  bool get _active => _player?._active ?? false;

  String get _type;

  /// Sets the [enabled] status of this audio effect.
  Future<void> setEnabled({required bool enabled}) async {
    _enabledSubject.add(enabled);
    if (_active) {
      await (await _player!._platform).audioEffectSetEnabled(
        AudioEffectSetEnabledRequest(type: _type, enabled: enabled),
      );
    }
  }

  AudioEffectMessage _toMessage();
}

/// An [AudioEffect] that supports Android. On other platforms its settings are
/// kept but never sent to the platform player.
mixin AndroidAudioEffect on AudioEffect {
  @override
  bool get _active => _isAndroid() && super._active;
}

/// An Android [AudioEffect] that boosts the volume of the audio signal to a
/// target gain, which defaults to zero.
class AndroidLoudnessEnhancer extends AudioEffect with AndroidAudioEffect {
  final _targetGainSubject = BehaviorSubject<double>.seeded(0);

  @override
  String get _type => 'AndroidLoudnessEnhancer';

  /// The target gain in decibels.
  double get targetGain => _targetGainSubject.nullableValue!;

  /// A stream of the current target gain in decibels.
  Stream<double> get targetGainStream => _targetGainSubject.stream;

  /// Sets the target gain to a value in decibels.
  Future<void> setTargetGain(double targetGain) async {
    _targetGainSubject.add(targetGain);
    if (_active) {
      await (await _player!._platform).androidLoudnessEnhancerSetTargetGain(
        AndroidLoudnessEnhancerSetTargetGainRequest(targetGain: targetGain),
      );
    }
  }

  @override
  AudioEffectMessage _toMessage() => AndroidLoudnessEnhancerMessage(enabled: enabled, targetGain: targetGain);
}

/// A frequency band within an [AndroidEqualizer].
class AndroidEqualizerBand {
  new _({
    required this._player,
    required this.index,
    required this.lowerFrequency,
    required this.upperFrequency,
    required this.centerFrequency,
    required double gain,
  }) {
    _gainSubject.add(gain);
  }

  factory _fromMessage(AudioPlayer player, AndroidEqualizerBandMessage message) => AndroidEqualizerBand._(
    player: player,
    index: message.index,
    lowerFrequency: message.lowerFrequency,
    upperFrequency: message.upperFrequency,
    centerFrequency: message.centerFrequency,
    gain: message.gain,
  );

  final AudioPlayer _player;

  /// A zero-based index of the position of this band within its [AndroidEqualizer].
  final int index;

  /// The lower frequency of this band in hertz.
  final double lowerFrequency;

  /// The upper frequency of this band in hertz.
  final double upperFrequency;

  /// The center frequency of this band in hertz.
  final double centerFrequency;
  final _gainSubject = BehaviorSubject<double>();

  /// The gain for this band in decibels.
  double get gain => _gainSubject.nullableValue!;

  /// A stream of the current gain for this band in decibels.
  Stream<double> get gainStream => _gainSubject.stream;

  /// Sets the gain for this band in decibels.
  Future<void> setGain(double gain) async {
    _gainSubject.add(gain);
    if (_player._active) {
      await (await _player._platform).androidEqualizerBandSetGain(
        AndroidEqualizerBandSetGainRequest(bandIndex: index, gain: gain),
      );
    }
  }

  /// Restores the gain after reactivating.
  Future<void> _restore(AudioPlayerInstancePlatform platform) async {
    await platform.androidEqualizerBandSetGain(AndroidEqualizerBandSetGainRequest(bandIndex: index, gain: gain));
  }
}

/// The parameter values of an [AndroidEqualizer].
class AndroidEqualizerParameters {
  new({required this.minDecibels, required this.maxDecibels, required this.bands});

  factory _fromMessage(AudioPlayer player, AndroidEqualizerParametersMessage message) => AndroidEqualizerParameters(
    minDecibels: message.minDecibels,
    maxDecibels: message.maxDecibels,
    bands: message.bands.map((bandMessage) => AndroidEqualizerBand._fromMessage(player, bandMessage)).toList(),
  );

  /// The minimum gain value supported by the equalizer.
  final double minDecibels;

  /// The maximum gain value supported by the equalizer.
  final double maxDecibels;

  /// The frequency bands of the equalizer.
  final List<AndroidEqualizerBand> bands;

  /// Restores platform state after reactivating.
  Future<void> _restore(AudioPlayerInstancePlatform platform) async {
    for (final band in bands) {
      await band._restore(platform);
    }
  }
}

/// An [AudioEffect] for Android that can adjust the gain for different
/// frequency bands of an [AudioPlayer]'s audio signal.
class AndroidEqualizer extends AudioEffect with AndroidAudioEffect {
  final Completer<AndroidEqualizerParameters> _parametersCompleter = Completer<AndroidEqualizerParameters>();

  @override
  String get _type => 'AndroidEqualizer';

  @override
  Future<void> _activate(AudioPlayerInstancePlatform platform) async {
    await super._activate(platform);
    if (_parametersCompleter.isCompleted) {
      await (await parameters)._restore(platform);
      return;
    }
    final response = await platform.androidEqualizerGetParameters(AndroidEqualizerGetParametersRequest());
    final receivedParameters = AndroidEqualizerParameters._fromMessage(_player!, response.parameters);
    _parametersCompleter.complete(receivedParameters);
  }

  /// The parameter values of this equalizer.
  Future<AndroidEqualizerParameters> get parameters => _parametersCompleter.future;

  @override
  AudioEffectMessage _toMessage() => AndroidEqualizerMessage(
    enabled: enabled,
    // Parameters are only communicated from the platform.
    parameters: null,
  );
}
