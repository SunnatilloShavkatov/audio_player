part of '../audio_player.dart';

/// Specifies a source of audio to be played. Audio sources are composable
/// using the subclasses of this class. The same [AudioSource] instance should
/// not be used simultaneously by more than one [AudioPlayer].
abstract class AudioSource {
  new({String? id}) : _id = id ?? _generateUuidV4();
  final String _id;
  AudioPlayer? _player;

  /// Creates an [AudioSource] from a [Uri] with optional headers by
  /// attempting to guess the type of stream. On iOS, this uses Apple's SDK to
  /// automatically detect the stream type. On Android, the type of stream will
  /// be guessed from the extension.
  ///
  /// If you are loading DASH or HLS streams that do not have standard "mpd" or
  /// "m3u8" extensions in their URIs, this method will fail to detect the
  /// stream type on Android. If you know in advance what type of audio stream
  /// it is, you should instantiate [DashAudioSource] or [HlsAudioSource]
  /// directly.
  ///
  /// If headers are set, audio_player will create a cleartext local HTTP proxy on
  /// your device to forward HTTP requests with headers included.
  ///
  /// The [tag] is for associating your app's own data with each audio source,
  /// e.g. title, cover art, a primary key for your DB. Such data can be
  /// conveniently retrieved from the tag while rendering the UI.
  ///
  /// When using audio_player_background, [tag] must be a MediaItem, a class
  /// provided by that package. If you wish to have more control over the tag
  /// for background audio purposes, consider using the plugin audio_service
  /// instead of audio_player_background.
  static UriAudioSource uri(Uri uri, {Map<String, String>? headers, Object? tag}) {
    bool hasExtension(Uri uri, String extension) =>
        uri.path.toLowerCase().endsWith('.$extension') || uri.fragment.toLowerCase().endsWith('.$extension');
    if (hasExtension(uri, 'mpd')) {
      return DashAudioSource(uri, headers: headers, tag: tag);
    } else if (hasExtension(uri, 'm3u8')) {
      return HlsAudioSource(uri, headers: headers, tag: tag);
    } else {
      return ProgressiveAudioSource(uri, headers: headers, tag: tag);
    }
  }

  /// Convenience method to create an audio source for a file.
  ///
  /// This is equivalent to:
  ///
  /// ```
  /// AudioSource.uri(Uri.file(filePath), tag: tag);
  /// ```
  static UriAudioSource file(String filePath, {Object? tag}) => AudioSource.uri(Uri.file(filePath), tag: tag);

  /// Convenience method to create an audio source for an asset.
  ///
  /// For assets within the same package, this is equivalent to:
  ///
  /// ```
  /// AudioSource.uri(Uri.parse('asset:///$assetPath'), tag: tag);
  /// ```
  ///
  /// If the asset is to be loaded from a different package, the [package]
  /// parameter must be given to specify the package name.
  static UriAudioSource asset(String assetPath, {String? package, Object? tag}) {
    final keyName = package == null ? assetPath : 'packages/$package/$assetPath';
    return AudioSource.uri(Uri.parse('asset:///$keyName'), tag: tag);
  }

  @mustCallSuper
  void _onAttach(AudioPlayer player) {
    _player = player;
    player._registerAudioSource(this);
  }

  @mustCallSuper
  Future<void> _onLoad() async {}

  String? get _userAgent => _player?._userAgent;

  void _shuffle({int? initialIndex});

  @mustCallSuper
  void _dispose() {
    // Without this we might make _player "late".
    _player = null;
  }

  AudioSourceMessage _toMessage();

  List<IndexedAudioSource> get sequence;

  List<int> get shuffleIndices;

  @override
  // Equality is by the immutable [_id]; the attached player is not part of it.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => _id.hashCode;

  @override
  // Equality is by the immutable [_id]; the attached player is not part of it.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) => other.runtimeType == runtimeType && other is AudioSource && other._id == _id;
}

/// An [AudioSource] that can appear in a sequence.
abstract class IndexedAudioSource extends AudioSource {
  new({this.tag, this.duration});

  final dynamic tag;
  Duration? duration;

  @override
  void _shuffle({int? initialIndex}) {}

  @override
  List<IndexedAudioSource> get sequence => [this];

  @override
  List<int> get shuffleIndices => [0];
}

/// An abstract class representing audio sources that are loaded from a URI.
abstract class UriAudioSource extends IndexedAudioSource {
  new(this.uri, {this.headers, super.tag, super.duration});

  final Uri uri;
  final Map<String, String>? headers;
  Uri? _overrideUri;

  /// If [uri] points to an asset, this gives us [_overrideUri] which is the URI
  /// of the copied asset on the filesystem, otherwise it gives us the original
  /// [uri].
  Uri get _effectiveUri => _overrideUri ?? uri;

  Map<String, String>? get _mergedHeaders =>
      headers == null && _userAgent == null ? null : {...?headers, 'User-Agent': ?_userAgent};

  @override
  Future<void> _onLoad() async {
    await super._onLoad();
    if (uri.scheme == 'asset') {
      _overrideUri = await _loadAsset(uri.pathSegments.join('/'));
    } else if (uri.scheme != 'file' &&
        !kIsWeb &&
        _player!._useProxyForRequestHeaders &&
        (headers != null || _player!._userAgent != null)) {
      await _player!._proxy.ensureRunning();
      _overrideUri = _player!._proxy.addUriAudioSource(this);
    }
  }

  Future<Uri> _loadAsset(String assetPath) async {
    if (kIsWeb) {
      // Mapping from extensions to content types for the web player. If an
      // extension is missing, please submit a pull request.
      const mimeTypes = {
        '.aac': 'audio/aac',
        '.mp3': 'audio/mpeg',
        '.ogg': 'audio/ogg',
        '.opus': 'audio/opus',
        '.wav': 'audio/wav',
        '.weba': 'audio/webm',
        '.mp4': 'audio/mp4',
        '.m4a': 'audio/mp4',
        '.aif': 'audio/x-aiff',
        '.aifc': 'audio/x-aiff',
        '.aiff': 'audio/x-aiff',
        '.m3u': 'audio/x-mpegurl',
      };
      // Default to 'audio/mpeg'
      final mimeType = mimeTypes[p.extension(assetPath).toLowerCase()] ?? 'audio/mpeg';
      return _encodeDataUrl(base64.encode((await rootBundle.load(assetPath)).buffer.asUint8List()), mimeType);
    } else {
      // For non-web platforms, extract the asset into a cache file and pass
      // that to the player.
      final file = await _getCacheFile(assetPath);
      if (!file.existsSync()) {
        // Write to a unique temporary file and rename it into place, so that an
        // interrupted write or a concurrent load never exposes a partial file.
        final tempFile = File('${file.path}.${_generateUuidV4()}.tmp');
        try {
          await tempFile.create(recursive: true);
          await tempFile.writeAsBytes((await rootBundle.load(assetPath)).buffer.asUint8List(), flush: true);
          await tempFile.rename(file.path);
        } catch (e) {
          if (tempFile.existsSync()) {
            await tempFile.delete();
          }
          rethrow;
        }
      }
      return Uri.file(file.path);
    }
  }

  /// Gets the cache file for an asset with the proper extension
  Future<File> _getCacheFile(String assetPath) async =>
      File(p.joinAll([(await _getCacheDir()).path, 'assets', ...Uri.parse(assetPath).pathSegments]));
}

/// An [AudioSource] representing a regular media file such as an MP3 or M4A
/// file. The following URI schemes are supported:
///
/// * file: loads from a local file (provided you give your app permission to
/// access that file).
/// * asset: loads from a Flutter asset (not supported on Web).
/// * http(s): loads from an HTTP(S) resource.
///
/// On platforms except for the web, the supplied [headers] will be passed with
/// the HTTP(S) request.
///
/// If headers are set, audio_player will create a cleartext local HTTP proxy on
/// your device to forward HTTP requests with headers included.
class ProgressiveAudioSource extends UriAudioSource {
  new(super.uri, {super.headers, super.tag, super.duration, this.options});

  final ProgressiveAudioSourceOptions? options;

  @override
  AudioSourceMessage _toMessage() => ProgressiveAudioSourceMessage(
    id: _id,
    uri: _effectiveUri.toString(),
    headers: _mergedHeaders,
    tag: tag,
    options: options?._toMessage(),
  );
}

/// An [AudioSource] representing a DASH stream. The following URI schemes are
/// supported:
///
/// * file: loads from a local file (provided you give your app permission to
/// access that file).
/// * asset: loads from a Flutter asset (not supported on Web).
/// * http(s): loads from an HTTP(S) resource.
///
/// On platforms except for the web, the supplied [headers] will be passed with
/// the HTTP(S) request. Currently headers are not applied recursively.
///
/// If headers are set, audio_player will create a cleartext local HTTP proxy on
/// your device to forward HTTP requests with headers included.
class DashAudioSource extends UriAudioSource {
  new(super.uri, {super.headers, super.tag, super.duration});

  @override
  AudioSourceMessage _toMessage() =>
      DashAudioSourceMessage(id: _id, uri: _effectiveUri.toString(), headers: _mergedHeaders, tag: tag);
}

/// An [AudioSource] representing an HLS stream. The following URI schemes are
/// supported:
///
/// * file: loads from a local file (provided you give your app permission to
/// access that file).
/// * asset: loads from a Flutter asset (not supported on Web).
/// * http(s): loads from an HTTP(S) resource.
///
/// On platforms except for the web, the supplied [headers] will be passed with
/// the HTTP(S) request. Currently headers are not applied recursively.
///
/// If headers are set, audio_player will create a cleartext local HTTP proxy on
/// your device to forward HTTP requests with headers included.
class HlsAudioSource extends UriAudioSource {
  new(super.uri, {super.headers, super.tag, super.duration});

  @override
  AudioSourceMessage _toMessage() =>
      HlsAudioSourceMessage(id: _id, uri: _effectiveUri.toString(), headers: _mergedHeaders, tag: tag);
}

/// An [AudioSource] for a period of silence.
///
/// NOTE: This is currently supported on Android only.
class SilenceAudioSource extends IndexedAudioSource {
  new({super.tag, required Duration super.duration});

  @override
  Duration get duration => super.duration!;

  @override
  set duration(covariant Duration duration) => super.duration = duration;

  @override
  AudioSourceMessage _toMessage() => SilenceAudioSourceMessage(id: _id, duration: duration);
}

Uri _encodeDataUrl(String base64Data, String mimeType) => Uri.parse('data:$mimeType;base64,$base64Data');
