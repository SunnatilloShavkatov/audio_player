part of '../audio_player.dart';

/// Access to [AudioPlayer] internals for this package's own tests.
///
/// Not part of the public API: `package:audio_player/audio_player.dart` hides
/// it, so only code that imports `package:audio_player/src/audio_player.dart`
/// directly can use it.
@visibleForTesting
extension AudioPlayerTestHooks on AudioPlayer {
  /// The idle platform of this player, created if it does not exist yet.
  @visibleForTesting
  AudioPlayerInstancePlatform get testIdlePlatform =>
      _idlePlatform ??
      (_idlePlatform = _IdleAudioPlayer(
        id: _id = AudioPlayer._generateId(),
        sequenceStream: sequenceStream,
        errorCode: playbackEvent.errorCode,
        errorMessage: playbackEvent.errorMessage,
      ));

  /// Converts [e] the way platform load errors are converted.
  @visibleForTesting
  Exception testConvertException(PlatformException e) => _convertException(e);

  /// Creates an internal playlist of [children] attached to [player].
  @visibleForTesting
  static AudioSource testCreatePlaylist(List<AudioSource> children, AudioPlayer player) =>
      _PlaylistAudioSource(children: children).._onAttach(player);

  /// The length of a playlist created by [testCreatePlaylist].
  @visibleForTesting
  static int testPlaylistLength(AudioSource playlist) => (playlist as _PlaylistAudioSource).length;

  /// The child at [index] of a playlist created by [testCreatePlaylist].
  @visibleForTesting
  static AudioSource testPlaylistGet(AudioSource playlist, int index) => (playlist as _PlaylistAudioSource)[index];

  /// Exercises `_PluginLoadRequest.resetInitialSeekValues` and an interrupted
  /// `checkInterruption`.
  @visibleForTesting
  static void testPluginLoadRequest() {
    final req =
        _PluginLoadRequest(
            audioSources: [],
            shuffleOrder: DefaultShuffleOrder(),
            initialIndex: 0,
            initialPosition: Duration.zero,
          )
          ..resetInitialSeekValues()
          ..interrupted = true;
    try {
      req.checkInterruption();
    } catch (_) {}
  }

  /// Encodes [base64Data] as a data URL of [mimeType].
  @visibleForTesting
  static Uri testEncodeDataUrl(String base64Data, String mimeType) => _encodeDataUrl(base64Data, mimeType);
}
