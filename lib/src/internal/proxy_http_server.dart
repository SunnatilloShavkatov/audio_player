part of '../audio_player.dart';

/// A local proxy HTTP server for making remote GET requests with headers.
class _ProxyHttpServer {
  late HttpServer _server;
  bool _running = false;

  /// Maps request keys to [_ProxyHandler]s.
  final Map<String, _ProxyHandler> _handlerMap = {};

  /// The port this server is bound to on localhost. This is set only after
  /// [start] has completed.
  int get port => _server.port;

  /// Registers a [UriAudioSource] to be served through this proxy. This may be
  /// called only after [start] has completed.
  Uri addUriAudioSource(UriAudioSource source) {
    final uri = source.uri;
    final headers = <String, String>{};
    if (source.headers != null) {
      headers.addAll(source.headers!.cast<String, String>());
    }
    final path = _requestKey(uri);
    _handlerMap[path] = _proxyHandlerForUri(uri, headers: headers, userAgent: source._player?._userAgent);
    return uri.replace(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: port);
  }

  /// Registers a [StreamAudioSource] to be served through this proxy. This may
  /// be called only after [start] has completed.
  Uri addStreamAudioSource(StreamAudioSource source) {
    final uri = _sourceUri(source);
    final path = _requestKey(uri);
    _handlerMap[path] = _proxyHandlerForSource(source);
    return uri;
  }

  Uri _sourceUri(StreamAudioSource source) =>
      Uri.http('${InternetAddress.loopbackIPv4.address}:$port', '/id/${source._id}');

  /// A unique key for each request that can be processed by this proxy,
  /// made up of the URL path and query string. It is not possible to
  /// simultaneously track requests that have the same URL path and query
  /// but differ in other respects such as the port or headers.
  String _requestKey(Uri uri) => '${uri.path}?${uri.query}';

  /// Starts the server if it is not already running.
  Future<dynamic> ensureRunning() async {
    if (_running) {
      return;
    }
    return await start();
  }

  /// Starts the server.
  Future<dynamic> start() async {
    _running = true;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(
      (request) {
        if (request.method == 'GET') {
          final uriPath = _requestKey(request.uri);
          final handler = _handlerMap[uriPath]!;
          handler(this, request);
        }
      },
      onDone: () {
        _running = false;
      },
      onError: (Object e, StackTrace st) {
        _running = false;
      },
    );
  }

  /// Stops the server
  Future<dynamic> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    return await _server.close();
  }
}

/// Encapsulates the start and end of an HTTP range request.
class _HttpRangeRequest {
  new(this.start, this.end);

  /// The starting byte position of the range request.
  final int start;

  /// The last byte position of the range request, or `null` if requesting
  /// until the end of the media.
  final int? end;

  /// The end byte position (exclusive), defaulting to `null`.
  int? get endEx => end == null ? null : end! + 1;

  /// Format a range header for this request.
  String get header => 'bytes=$start-${end != null ? (end! - 1).toString() : ""}';

  /// Creates an [_HttpRangeRequest] from [header].
  static _HttpRangeRequest? parse(List<String>? header) {
    if (header == null || header.isEmpty) {
      return null;
    }
    final match = RegExp(r'^bytes=(\d+)(-(\d+)?)?').firstMatch(header.first);
    if (match == null) {
      return null;
    }
    int? intGroup(int i) => match[i] != null ? int.parse(match[i]!) : null;
    return _HttpRangeRequest(intGroup(1)!, intGroup(3));
  }
}

/// Encapsulates the range information in an HTTP range response.
class _HttpRangeResponse {
  new(this.start, this.end, this.fullLength);

  /// The starting byte position of the range.
  final int start;

  /// The last byte position of the range.
  final int end;

  /// The total number of bytes in the entire media.
  final int? fullLength;

  /// The end byte position (exclusive).
  int? get endEx => end + 1;

  /// The number of bytes requested.
  int? get length => endEx == null ? null : endEx! - start;

  /// The content-range header value to use in HTTP responses.
  String get header => 'bytes $start-$end/${fullLength?.toString() ?? "*"}';
}

/// The type of functions that can handle HTTP requests sent to the proxy.
typedef _ProxyHandler = void Function(_ProxyHttpServer server, HttpRequest request);

/// A proxy handler for serving audio from a [StreamAudioSource].
_ProxyHandler _proxyHandlerForSource(StreamAudioSource source) {
  Future<void> handler(_ProxyHttpServer server, HttpRequest request) async {
    final rangeRequest = _HttpRangeRequest.parse(request.headers[HttpHeaders.rangeHeader]);

    request.response.headers.clear();

    StreamAudioResponse sourceResponse;
    Stream<List<int>> stream;
    try {
      sourceResponse = await source.request(rangeRequest?.start, rangeRequest?.endEx);
      stream = sourceResponse.stream;
    } catch (e, st) {
      // Surface proxy failures during development; there is no logger here.
      // ignore: avoid_print
      print('Proxy request failed: $e\n$st');

      request.response.headers.clear();
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }

    request.response.headers.set(HttpHeaders.contentTypeHeader, sourceResponse.contentType);

    if (sourceResponse.rangeRequestsSupported) {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }

    if (rangeRequest != null && sourceResponse.offset != null) {
      final range = _HttpRangeResponse(
        sourceResponse.offset!,
        sourceResponse.offset! + sourceResponse.contentLength! - 1,
        sourceResponse.sourceLength,
      );
      request.response.contentLength = range.length ?? -1;
      request.response.headers.set(HttpHeaders.contentRangeHeader, range.header);
      request.response.statusCode = 206;
    } else {
      request.response.contentLength = sourceResponse.contentLength ?? -1;
      request.response.statusCode = 200;
    }

    final completer = Completer<void>();
    final subscription = stream.listen(request.response.add, onError: (e, st) {}, onDone: completer.complete);

    unawaited(
      request.response.done.then((value) {
        unawaited(subscription.cancel());
      }),
    );

    await completer.future;

    await request.response.close();
  }

  return handler;
}

/// A proxy handler for serving audio from a URI with optional headers.
_ProxyHandler _proxyHandlerForUri(Uri uri, {Map<String, String>? headers, String? userAgent}) {
  // Keep redirected [Uri] to speed-up requests
  Uri? redirectedUri;
  Future<void> handler(_ProxyHttpServer server, HttpRequest request) async {
    final client = _createHttpClient(userAgent: userAgent);
    // Try to make normal request
    String? host;
    try {
      final requestHeaders = <String, String>{};
      request.headers.forEach((name, value) => requestHeaders[name] = value.join(', '));
      // write supplied headers last (to ensure supplied headers aren't overwritten)
      headers?.forEach((name, value) => requestHeaders[name] = value);
      final originRequest = await _getUrl(client, redirectedUri ?? uri, headers: requestHeaders);
      host = originRequest.headers.value(HttpHeaders.hostHeader);
      final originResponse = await originRequest.close();
      if (originResponse.redirects.isNotEmpty) {
        redirectedUri = originResponse.redirects.last.location;
      }

      request.response.headers.clear();
      originResponse.headers.forEach((name, value) {
        final filteredValue = value.map((e) => e.replaceAll(RegExp(r'[^\x09\x20-\x7F]'), '?')).toList();
        request.response.headers.set(name, filteredValue);
      });
      request.response.statusCode = originResponse.statusCode;

      // Send response
      if (headers != null && request.uri.path.toLowerCase().endsWith('.m3u8') ||
          [
            'application/x-mpegURL',
            'application/vnd.apple.mpegurl',
          ].contains(request.headers.value(HttpHeaders.contentTypeHeader))) {
        // If this is an m3u8 file with headers, prepare the nested URIs.
        // TODO(SunnatilloShavkatov): Handle other playlist formats similarly?
        final m3u8 = await originResponse.transform(utf8.decoder).join();
        for (var line in const LineSplitter().convert(m3u8)) {
          line = line.replaceAllMapped(RegExp('#EXT-X-MEDIA:.*?URI="(.*?)".*'), (m) => m[1]!);
          line = line.replaceAll(RegExp(r'#.*$'), '').trim();
          if (line.isEmpty) {
            continue;
          }
          try {
            final rawNestedUri = Uri.parse(line);
            if (rawNestedUri.hasScheme) {
              // Don't propagate headers
              server.addUriAudioSource(AudioSource.uri(rawNestedUri));
            } else {
              // This is a resource on the same server, so propagate the headers.
              final basePath = rawNestedUri.path.startsWith('/') ? '' : uri.path.replaceAll(RegExp(r'/[^/]*$'), '/');
              final nestedUri = uri.replace(path: '$basePath${rawNestedUri.path}');
              server.addUriAudioSource(AudioSource.uri(nestedUri, headers: headers));
            }
          } catch (e) {
            // ignore malformed lines
          }
        }
        request.response.add(utf8.encode(m3u8));
      } else {
        request.response.bufferOutput = false;
        var done = false;
        unawaited(request.response.done.then((_) => done = true));
        await for (final chunk in originResponse) {
          if (done) {
            break;
          }
          request.response.add(chunk);
          await request.response.flush();
        }
      }
      await request.response.flush();
      await request.response.close();
    } on HttpException {
      // We likely are dealing with a streaming protocol
      if (uri.scheme == 'http') {
        // Try parsing HTTP 0.9 response
        //request.response.headers.clear();
        final socket = await Socket.connect(uri.host, uri.port);
        final clientSocket = await request.response.detachSocket(writeHeaders: false);
        final done = Completer<dynamic>();
        socket.listen(
          clientSocket.add,
          onDone: () async {
            await clientSocket.flush();
            unawaited(socket.close());
            unawaited(clientSocket.close());
            done.complete();
          },
        );
        // Rewrite headers
        final headers = <String, String?>{};
        request.headers.forEach((name, value) {
          if (name.toLowerCase() != HttpHeaders.hostHeader) {
            headers[name] = value.join(',');
          }
        });
        for (final name in headers.keys) {
          headers[name] = headers[name];
        }
        socket.write('GET ${uri.path} HTTP/1.1\n');
        if (host != null) {
          socket.write('Host: $host\n');
        }
        for (final name in headers.keys) {
          socket.write('$name: ${headers[name]}\n');
        }
        socket.write('\n');
        await socket.flush();
        await done.future;
      }
    }
  }

  return handler;
}
