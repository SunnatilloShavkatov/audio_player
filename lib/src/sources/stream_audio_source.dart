part of '../audio_player.dart';

/// An [AudioSource] that provides audio dynamically. Subclasses must override
/// [request] to provide the encoded audio data. This API is experimental.
@experimental
abstract class StreamAudioSource extends IndexedAudioSource {
  new({super.tag});

  Uri? _uri;

  @override
  Future<void> _onLoad() async {
    await super._onLoad();
    if (kIsWeb) {
      final response = await request();
      _uri ??= _encodeDataUrl(await base64.encoder.bind(response.stream).join(), response.contentType);
    } else {
      await _player!._proxy.ensureRunning();
      _uri = _player!._proxy.addStreamAudioSource(this);
    }
  }

  /// Used by the player to request a byte range of encoded audio data in small
  /// chunks, from byte position [start] inclusive (or from the beginning of the
  /// audio data if not specified) to [end] exclusive (or the end of the audio
  /// data if not specified). If the returned future completes with an error,
  /// a 500 response will be sent back to the player.
  Future<StreamAudioResponse> request([int? start, int? end]);

  @override
  AudioSourceMessage _toMessage() => ProgressiveAudioSourceMessage(id: _id, uri: _uri.toString(), tag: tag);
}

/// The response for a [StreamAudioSource]. This API is experimental.
@experimental
class StreamAudioResponse {
  new({
    this.rangeRequestsSupported = true,
    required this.sourceLength,
    required this.contentLength,
    required this.offset,
    required this.stream,
    required this.contentType,
  });

  /// Indicates to the client whether or not range requests are supported for
  /// the requested media. If `true`, the client may make further requests
  /// specifying the `start` and possibly also the `end` parameters of the range
  /// request, otherwise these will both be null.
  final bool rangeRequestsSupported;

  /// When responding to a range request, this holds the byte length of the
  /// entire media, otherwise it holds `null`.
  final int? sourceLength;

  /// The number of bytes returned in this response, or `null` if unknown. Note:
  /// this may be different from the length of the entire media for a range
  /// request.
  final int? contentLength;

  /// The starting byte position of the response data if responding to a range
  /// request.
  final int? offset;

  /// The MIME type of the audio.
  final String contentType;

  /// The audio content returned by this response.
  final Stream<List<int>> stream;
}

/// This is an experimental audio source that caches the audio while it is being
/// downloaded and played. It is not supported on platforms that do not provide
/// access to the file system (e.g. web).
@experimental
class LockCachingAudioSource extends StreamAudioSource {
  /// Creates a [LockCachingAudioSource] to that provides [uri] to the player
  /// while simultaneously caching it to [cacheFile]. If no cache file is
  /// supplied, audio_player will allocate a cache file internally.
  ///
  /// If headers are set, audio_player will create a cleartext local HTTP proxy on
  /// your device to forward HTTP requests with headers included.
  new(this.uri, {this.headers, File? cacheFile, super.tag})
    : cacheFile = cacheFile != null ? Future.value(cacheFile) : _getCacheFile(uri) {
    unawaited(_init());
  }

  Future<HttpClientResponse>? _response;
  final Uri uri;
  final Map<String, String>? headers;
  final Future<File> cacheFile;
  int _progress = 0;
  final _requests = <_StreamingByteRangeRequest>[];
  final _downloadProgressSubject = BehaviorSubject<double>();
  bool _downloading = false;

  Future<void> _init() async {
    final cacheFile = await this.cacheFile;
    _downloadProgressSubject.add(cacheFile.existsSync() ? 1.0 : 0.0);
  }

  /// Returns a [UriAudioSource] resolving directly to the cache file if it
  /// exists, otherwise returns `this`. This can be
  Future<IndexedAudioSource> resolve() async {
    final file = await cacheFile;
    return file.existsSync() ? AudioSource.uri(Uri.file(file.path)) : this;
  }

  /// Emits the current download progress as a double value from 0.0 (nothing
  /// downloaded) to 1.0 (download complete).
  Stream<double> get downloadProgressStream => _downloadProgressSubject.stream;

  /// Removes the underlying cache files. It is an error to clear the cache
  /// while a download is in progress.
  Future<void> clearCache() async {
    if (_downloading) {
      throw Exception('Cannot clear cache while download is in progress');
    }
    _response = null;
    final cacheFile = await this.cacheFile;
    if (cacheFile.existsSync()) {
      await cacheFile.delete();
    }
    final mimeFile = await _mimeFile;
    if (mimeFile.existsSync()) {
      await mimeFile.delete();
    }
    _progress = 0;
    _downloadProgressSubject.add(0);
  }

  /// Gets the cache file for [uri] with the proper extension.
  static Future<File> _getCacheFile(Uri uri) async => File(
    p.joinAll([
      (await _getCacheDir()).path,
      'remote',
      sha256.convert(utf8.encode(uri.toString())).toString() + p.extension(uri.path),
    ]),
  );

  Future<File> get _partialCacheFile async => File('${(await cacheFile).path}.part');

  /// We use this to record the original content type of the downloaded audio.
  /// NOTE: We could instead rely on the cache file extension, but the original
  /// URL might not provide a correct extension. As a fallback, we could map the
  /// MIME type to an extension but we will need a complete dictionary.
  Future<File> get _mimeFile async => File('${(await cacheFile).path}.mime');

  Future<String> _readCachedMimeType() async {
    final file = await _mimeFile;
    if (file.existsSync()) {
      return (await _mimeFile).readAsString();
    } else {
      return 'audio/mpeg';
    }
  }

  /// Starts downloading the whole audio file to the cache and fulfill byte-range
  /// requests during the download. There are 3 scenarios:
  ///
  /// 1. If the byte range request falls entirely within the cache region, it is
  /// fulfilled from the cache.
  /// 2. If the byte range request overlaps the cached region, the first part is
  /// fulfilled from the cache, and the region beyond the cache is fulfilled
  /// from a memory buffer of the downloaded data.
  /// 3. If the byte range request is entirely outside the cached region, a
  /// separate HTTP request is made to fulfill it while the download of the
  /// entire file continues in parallel.
  Future<HttpClientResponse> _fetch() async {
    _downloading = true;
    final cacheFile = await this.cacheFile;
    final partialCacheFile = await _partialCacheFile;

    File getEffectiveCacheFile() => partialCacheFile.existsSync() ? partialCacheFile : cacheFile;

    final httpClient = _createHttpClient(userAgent: _player?._userAgent);
    final httpRequest = await _getUrl(httpClient, uri, headers: headers);
    final response = await httpRequest.close();
    if (response.statusCode != 200) {
      httpClient.close();
      throw Exception('HTTP Status Error: ${response.statusCode}');
    }
    (await _partialCacheFile).createSync(recursive: true);
    // Closed in the onDone and onError handlers below.
    final sink = (await _partialCacheFile).openWrite();
    final sourceLength = response.contentLength == -1 ? null : response.contentLength;
    final mimeType = response.headers.contentType.toString();
    final acceptRanges = response.headers.value(HttpHeaders.acceptRangesHeader);
    final originSupportsRangeRequests = acceptRanges != null && acceptRanges != 'none';
    final mimeFile = await _mimeFile;
    await mimeFile.writeAsString(mimeType);
    final inProgressResponses = <_InProgressCacheResponse>[];
    late StreamSubscription<List<int>> subscription;
    var percentProgress = 0;
    void updateProgress(int newPercentProgress) {
      if (newPercentProgress != percentProgress) {
        percentProgress = newPercentProgress;
        _downloadProgressSubject.add(percentProgress / 100);
      }
    }

    _progress = 0;
    subscription = response.listen(
      (data) async {
        _progress += data.length;
        final newPercentProgress = (sourceLength == null)
            ? 0
            : (sourceLength == 0)
            ? 100
            : (100 * _progress ~/ sourceLength);
        updateProgress(newPercentProgress);
        sink.add(data);
        final readyRequests = _requests
            .where((request) => !originSupportsRangeRequests || request.start == null || (request.start!) < _progress)
            .toList();
        final notReadyRequests = _requests
            .where((request) => originSupportsRangeRequests && request.start != null && (request.start!) >= _progress)
            .toList();
        // Add this live data to any responses in progress.
        for (final cacheResponse in inProgressResponses) {
          final end = cacheResponse.end;
          if (end != null && _progress >= end) {
            // We've received enough data to fulfill the byte range request.
            final subEnd = min(data.length, max(0, data.length - (_progress - end)));
            cacheResponse.controller.add(data.sublist(0, subEnd));
            unawaited(cacheResponse.controller.close());
          } else {
            cacheResponse.controller.add(data);
          }
        }
        inProgressResponses.removeWhere((element) => element.controller.isClosed);
        if (_requests.isEmpty) {
          return;
        }
        // Prevent further data coming from the HTTP source until we have set up
        // an entry in inProgressResponses to continue receiving live HTTP data.
        subscription.pause();
        await sink.flush();
        // Process any requests that start within the cache.
        for (final request in readyRequests) {
          _requests.remove(request);
          int? start;
          int? end;
          if (originSupportsRangeRequests) {
            start = request.start;
            end = request.end;
          } else {
            // If the origin doesn't support range requests, the proxy should also
            // ignore range requests and instead serve a complete 200 response
            // which the client (AV or exo player) should know how to deal with.
          }
          final effectiveStart = start ?? 0;
          final effectiveEnd = end ?? sourceLength;
          Stream<List<int>> responseStream;
          if (effectiveEnd != null && effectiveEnd <= _progress) {
            responseStream = getEffectiveCacheFile().openRead(effectiveStart, effectiveEnd);
          } else {
            final cacheResponse = _InProgressCacheResponse(end: effectiveEnd);
            inProgressResponses.add(cacheResponse);
            responseStream = Rx.concatEager([
              // NOTE: The cache file part of the stream must not overlap with
              // the live part. "_progress" should
              // to the cache file at the time
              getEffectiveCacheFile().openRead(effectiveStart, _progress),
              cacheResponse.controller.stream,
            ]);
          }
          request.complete(
            StreamAudioResponse(
              rangeRequestsSupported: originSupportsRangeRequests,
              sourceLength: start != null ? sourceLength : null,
              contentLength: effectiveEnd != null ? effectiveEnd - effectiveStart : null,
              offset: start,
              contentType: mimeType,
              stream: responseStream.asBroadcastStream(),
            ),
          );
        }
        subscription.resume();
        // Process any requests that start beyond the cache.
        for (final request in notReadyRequests) {
          _requests.remove(request);
          final start = request.start!;
          final end = request.end ?? sourceLength;
          final httpClient = _createHttpClient(userAgent: _player?._userAgent);

          final rangeRequest = _HttpRangeRequest(start, end);
          unawaited(
            _getUrl(httpClient, uri, headers: {...?headers, HttpHeaders.rangeHeader: rangeRequest.header})
                .then(
                  (httpRequest) async {
                    final response = await httpRequest.close();
                    if (response.statusCode != 206) {
                      httpClient.close();
                      throw Exception('HTTP Status Error: ${response.statusCode}');
                    }
                    request.complete(
                      StreamAudioResponse(
                        rangeRequestsSupported: originSupportsRangeRequests,
                        sourceLength: sourceLength,
                        contentLength: end != null ? end - start : null,
                        offset: start,
                        contentType: mimeType,
                        stream: response.asBroadcastStream(),
                      ),
                    );
                  },
                  onError: (Object e, StackTrace? stackTrace) {
                    request.fail(e, stackTrace);
                  },
                )
                .onError((Object e, StackTrace st) {
                  request.fail(e, st);
                }),
          );
        }
      },
      onDone: () async {
        if (sourceLength == null) {
          updateProgress(100);
        }
        for (final cacheResponse in inProgressResponses) {
          if (!cacheResponse.controller.isClosed) {
            unawaited(cacheResponse.controller.close());
          }
        }
        // Flush and close before renaming so the cache file is complete.
        await sink.close();
        (await _partialCacheFile).renameSync(cacheFile.path);
        await subscription.cancel();
        httpClient.close();
        _downloading = false;
      },
      onError: (Object e, StackTrace stackTrace) async {
        try {
          await sink.close();
        } catch (_) {
          // The sink may already be in an error state; the partial file is discarded anyway.
        }
        (await _partialCacheFile).deleteSync();
        httpClient.close();
        // Fail all pending requests
        for (final req in _requests) {
          req.fail(e, stackTrace);
        }
        _requests.clear();
        // Close all in progress requests
        for (final res in inProgressResponses) {
          res.controller.addError(e, stackTrace);
          unawaited(res.controller.close());
        }
        _downloading = false;
      },
      cancelOnError: true,
    );
    return response;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final cacheFile = await this.cacheFile;
    if (cacheFile.existsSync()) {
      final sourceLength = cacheFile.lengthSync();
      return StreamAudioResponse(
        sourceLength: start != null ? sourceLength : null,
        contentLength: (end ?? sourceLength) - (start ?? 0),
        offset: start,
        contentType: await _readCachedMimeType(),
        stream: cacheFile.openRead(start, end).asBroadcastStream(),
      );
    }
    final byteRangeRequest = _StreamingByteRangeRequest(start, end);
    _requests.add(byteRangeRequest);
    _response ??= _fetch().catchError((Object error, StackTrace? stackTrace) {
      // So that we can restart later
      _response = null;
      // Cancel any pending request
      for (final req in _requests) {
        req.fail(error, stackTrace);
      }
      return Future<HttpClientResponse>.error(error, stackTrace);
    });
    return byteRangeRequest.future.then((response) {
      response.stream.listen(
        (event) {},
        onError: (Object e, StackTrace st) {
          // So that we can restart later
          _response = null;
          // Cancel any pending request
          for (final req in _requests) {
            req.fail(e, st);
          }
        },
      );
      return response;
    });
  }
}

/// When a byte range request on a [LockCachingAudioSource] overlaps partially
/// with the cache file and partially with the live HTTP stream, the consumer
/// needs to first consume the cached part before the live part. This class
/// provides a place to buffer the live part until the consumer reaches it, and
/// also keeps track of the [end] of the byte range so that the producer knows
/// when to stop adding data.
class _InProgressCacheResponse {
  new({required this.end});

  // NOTE: This isn't necessarily memory efficient. Since the entire audio file
  // will likely be downloaded at a faster rate than the rate at which the
  // player is consuming audio data, it is also likely that this buffered data
  // will never be used.
  // TODO(SunnatilloShavkatov): Improve this code.
  // ignore: close_sinks
  final controller = ReplaySubject<List<int>>();
  final int? end;
}

/// Request parameters for a [StreamAudioSource].
class _StreamingByteRangeRequest {
  new(this.start, this.end);

  /// The start of the range request.
  final int? start;

  /// The end of the range request.
  final int? end;

  /// Completes when the response is available.
  final _completer = Completer<StreamAudioResponse>();

  /// The response for this request.
  Future<StreamAudioResponse> get future => _completer.future;

  /// Completes this request with the given [response].
  void complete(StreamAudioResponse response) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete(response);
  }

  /// Fails this request with the given [error] and [stackTrace].
  void fail(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.completeError(error, stackTrace);
  }
}
