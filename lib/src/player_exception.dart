/// Captures the details of any error accessing, loading or playing an audio
/// source, including an invalid or inaccessible URL, or an audio encoding that
/// could not be understood.
class PlayerException implements Exception {
  new(this.code, this.message, this.index);

  /// On iOS and macOS, maps to `NSError.code`. On Android, maps to
  /// `ExoPlaybackException.type`.
  final int code;

  /// On iOS and macOS, maps to `NSError.localizedDescription`. On Android,
  /// maps to `ExoPlaybackException.getMessage()`.
  final String? message;

  /// The index of the audio source associated with this error.
  final int? index;

  @override
  String toString() => '($code) $message';
}

/// An error that occurs when one operation on the player has been interrupted
/// (e.g. by another simultaneous operation).
class PlayerInterruptedException implements Exception {
  new(this.message);

  final String? message;

  @override
  String toString() => '$message';
}
