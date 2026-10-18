part of 'audio_player.dart';

/// The attributes that describe how an [AudioPlayer] plays audio on Android.
///
/// They decide how Android routes and mixes the audio, and how the player
/// reacts to audio focus changes (for example, speech is paused rather than
/// ducked when another app briefly takes the audio focus). Pass them to
/// [AudioPlayer.setAndroidAudioAttributes]. They have no effect on other
/// platforms.
@immutable
class AndroidAudioAttributes {
  const new({
    this.contentType = AndroidAudioContentType.unknown,
    this.flags = AndroidAudioFlags.none,
    this.usage = AndroidAudioUsage.unknown,
  });

  /// What type of audio is played.
  final AndroidAudioContentType contentType;

  /// How the playback is to be affected.
  final AndroidAudioFlags flags;

  /// Why the audio is played.
  final AndroidAudioUsage usage;

  @override
  bool operator ==(Object other) =>
      other is AndroidAudioAttributes &&
      contentType == other.contentType &&
      flags == other.flags &&
      usage == other.usage;

  @override
  int get hashCode => Object.hash(contentType, flags, usage);
}

/// The type of audio that [AndroidAudioAttributes] describe.
///
/// The order matches the `CONTENT_TYPE_*` constants of Android's
/// `AudioAttributes`, because [index] is sent to the platform.
enum AndroidAudioContentType { unknown, speech, music, movie, sonification }

/// The flags of [AndroidAudioAttributes].
@immutable
class AndroidAudioFlags {
  /// Creates flags from the raw `FLAG_*` bits of Android's `AudioAttributes`.
  const new(this.value);

  /// No flags.
  static const none = AndroidAudioFlags(0);

  /// Audibility of the audio is enforced, even where the platform would
  /// otherwise silence it (for example, camera shutter sounds in some regions).
  static const audibilityEnforced = AndroidAudioFlags(1);

  /// The raw `FLAG_*` bits.
  final int value;

  /// These flags combined with [flag].
  AndroidAudioFlags operator |(AndroidAudioFlags flag) => AndroidAudioFlags(value | flag.value);

  /// The flags that are set in both these flags and [flag].
  AndroidAudioFlags operator &(AndroidAudioFlags flag) => AndroidAudioFlags(value & flag.value);

  /// Whether all of the flags in [flags] are set.
  bool contains(AndroidAudioFlags flags) => flags.value & value == flags.value;

  @override
  bool operator ==(Object other) => other is AndroidAudioFlags && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Why the audio of [AndroidAudioAttributes] is played.
///
/// The values match the `USAGE_*` constants of Android's `AudioAttributes`.
@immutable
class AndroidAudioUsage {
  const new _(this.value);

  static const unknown = AndroidAudioUsage._(0);
  static const media = AndroidAudioUsage._(1);
  static const voiceCommunication = AndroidAudioUsage._(2);
  static const voiceCommunicationSignalling = AndroidAudioUsage._(3);
  static const alarm = AndroidAudioUsage._(4);
  static const notification = AndroidAudioUsage._(5);
  static const notificationRingtone = AndroidAudioUsage._(6);
  static const notificationCommunicationRequest = AndroidAudioUsage._(7);
  static const notificationCommunicationInstant = AndroidAudioUsage._(8);
  static const notificationCommunicationDelayed = AndroidAudioUsage._(9);
  static const notificationEvent = AndroidAudioUsage._(10);
  static const assistanceAccessibility = AndroidAudioUsage._(11);
  static const assistanceNavigationGuidance = AndroidAudioUsage._(12);
  static const assistanceSonification = AndroidAudioUsage._(13);
  static const game = AndroidAudioUsage._(14);
  static const assistant = AndroidAudioUsage._(16);

  /// The raw `USAGE_*` constant.
  final int value;

  @override
  bool operator ==(Object other) => other is AndroidAudioUsage && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
