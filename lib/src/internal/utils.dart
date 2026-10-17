part of '../audio_player.dart';

Future<Directory> _getCacheDir() async => Directory(p.join((await getTemporaryDirectory()).path, 'audio_player_cache'));

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

bool _isAndroid() => !kIsWeb && Platform.isAndroid;

bool _isDarwin() => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

bool _isUnitTest() => !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

/// Backwards compatible extensions on rxdart's ValueStream
extension _ValueStreamExtension<T> on ValueStream<T> {
  /// Backwards compatible version of valueOrNull.
  T? get nullableValue => hasValue ? value : null;
}

Future<HttpClientRequest> _getUrl(HttpClient client, Uri uri, {Map<String, String>? headers}) async {
  final request = await client.getUrl(uri);
  if (headers != null) {
    final host = request.headers.value(HttpHeaders.hostHeader);
    request.headers.clear();
    request.headers.set(HttpHeaders.contentLengthHeader, '0');
    headers.forEach((name, value) => request.headers.set(name, value));
    if (host != null) {
      request.headers.set(HttpHeaders.hostHeader, host);
    }
    if (client.userAgent != null) {
      request.headers.set(HttpHeaders.userAgentHeader, client.userAgent!);
    }
  }
  // Match ExoPlayer's native behavior
  request.maxRedirects = 20;
  return request;
}

HttpClient _createHttpClient({String? userAgent}) {
  final client = HttpClient();
  if (userAgent != null) {
    client.userAgent = userAgent;
  }
  return client;
}
