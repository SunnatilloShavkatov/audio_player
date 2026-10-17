part of '../audio_player.dart';

Future<Directory> _getCacheDir() async =>
    Directory(_joinPath([(await getTemporaryDirectory()).path, 'audio_player_cache']));

/// Joins [parts] with [Platform.pathSeparator]. Empty parts are skipped, and no
/// separator is added after a part that already ends with one.
String _joinPath(Iterable<String> parts) => parts
    .where((part) => part.isNotEmpty)
    .fold(
      '',
      (path, part) =>
          path.isEmpty || path.endsWith(Platform.pathSeparator) ? '$path$part' : '$path${Platform.pathSeparator}$part',
    );

final _secureRandom = Random.secure();

/// Generates a random (version 4) UUID using a cryptographically secure
/// random number generator.
String _generateUuidV4() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The platform to behave as instead of the host. Only this package's own
/// tests, which run on the development machine, set it (through
/// [AudioPlayerTestHooks.testTargetPlatform]).
TargetPlatform? _testTargetPlatform;

bool _isAndroid() => _testTargetPlatform == null ? Platform.isAndroid : _testTargetPlatform == TargetPlatform.android;

/// Backwards compatible extensions on rxdart's ValueStream
extension _ValueStreamExtension<T> on ValueStream<T> {
  /// Backwards compatible version of valueOrNull.
  T? get nullableValue => hasValue ? value : null;
}
