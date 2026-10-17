import 'dart:async';
import 'dart:io';

import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestHttpOverrides extends HttpOverrides;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _TestHttpOverrides();

  group('StreamAudioResponse', () {
    test('constructors and properties', () async {
      final resp = StreamAudioResponse(
        sourceLength: 100,
        contentLength: 50,
        offset: 10,
        stream: Stream.value([1, 2, 3]),
        contentType: 'audio/mpeg',
      );

      expect(resp.rangeRequestsSupported, isTrue);
      expect(resp.sourceLength, equals(100));
      expect(resp.contentLength, equals(50));
      expect(resp.offset, equals(10));
      expect(resp.contentType, equals('audio/mpeg'));
      expect(await resp.stream.first, equals([1, 2, 3]));
    });
  });

  group('LockCachingAudioSource', () {
    late HttpServer server;
    late Directory tempDir;
    late List<int> testData;
    Completer<void>? slowChunk2Completer;
    Completer<void>? slowChunk3Completer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lock_caching_test_');
      testData = List.generate(200, (i) => i % 256);
      slowChunk2Completer = null;
      slowChunk3Completer = null;

      server = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
        ..listen((request) async {
          if (request.uri.path == '/404.mp3') {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }

          if (request.uri.path == '/500.mp3') {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
            return;
          }

          final range = request.headers.value(HttpHeaders.rangeHeader);
          if (range != null && range.startsWith('bytes=')) {
            final parts = range.substring(6).split('-');
            final start = int.parse(parts[0]);
            final end = parts[1].isNotEmpty ? int.parse(parts[1]) : testData.length - 1;
            final chunk = testData.sublist(start, end + 1);

            request.response
              ..statusCode = HttpStatus.partialContent
              ..headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg')
              ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
              ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${testData.length}')
              ..contentLength = chunk.length
              ..add(chunk);
            await request.response.close();
            return;
          }

          if (request.uri.path == '/abort.mp3') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg')
              ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
              ..contentLength = testData.length;
            request.response.add(testData.sublist(0, 10));
            await request.response.flush();
            request.response.addError(const HttpException('Simulated connection reset'));
            await request.response.close().catchError((_) {});
            return;
          }

          if (request.uri.path == '/slow.mp3') {
            request.response.bufferOutput = false;
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg')
              ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
              ..contentLength = testData.length;
            request.response.add(testData.sublist(0, 30));
            await request.response.flush();
            if (slowChunk2Completer != null) {
              await slowChunk2Completer!.future;
            }
            request.response.add(testData.sublist(30, 60));
            await request.response.flush();
            if (slowChunk3Completer != null) {
              await slowChunk3Completer!.future;
            }
            request.response.add(testData.sublist(60));
            await request.response.close();
            return;
          }

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg')
            ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
            ..contentLength = testData.length
            ..add(testData);
          await request.response.close();
        });
    });

    tearDown(() async {
      await server.close(force: true);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('downloads, caches, resolves, and serves cached data', () async {
      final cacheFile = File('${tempDir.path}/test.mp3');
      final source = LockCachingAudioSource(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server.port}/test.mp3'),
        cacheFile: cacheFile,
        tag: 'tag1',
      );

      expect(source.tag, equals('tag1'));

      final unresolved = await source.resolve();
      expect(unresolved, equals(source));

      final progressEvents = <double>[];
      final sub = source.downloadProgressStream.listen(progressEvents.add);

      final resp1 = await source.request(0, 50);
      final bytes1 = <int>[];
      await resp1.stream.forEach(bytes1.addAll);
      expect(bytes1, equals(testData.sublist(0, 50)));

      // Wait until download completes and cache file exists
      while (!cacheFile.existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(cacheFile.existsSync(), isTrue);
      expect(cacheFile.readAsBytesSync(), equals(testData));

      // After download, resolve returns UriAudioSource
      final resolved = await source.resolve();
      expect(resolved, isA<UriAudioSource>());
      expect((resolved as UriAudioSource).uri, equals(Uri.file(cacheFile.path)));

      // Requesting from cached source reads from cache file
      final cachedResp = await source.request(10, 60);
      expect(cachedResp.contentLength, equals(50));
      expect(cachedResp.offset, equals(10));
      final cachedBytes = <int>[];
      await cachedResp.stream.forEach(cachedBytes.addAll);
      expect(cachedBytes, equals(testData.sublist(10, 60)));

      // Clear cache
      await source.clearCache();
      expect(cacheFile.existsSync(), isFalse);
      expect(progressEvents, contains(0.0));

      await sub.cancel();
    });

    test('slow stream with concurrent in-progress and out-of-band range requests', () async {
      slowChunk2Completer = Completer<void>();
      slowChunk3Completer = Completer<void>();
      final cacheFile = File('${tempDir.path}/slow.mp3');
      final source = LockCachingAudioSource(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server.port}/slow.mp3'),
        cacheFile: cacheFile,
      );

      final resp1 = await source.request(0, 20);
      expect(await resp1.stream.first, equals(testData.sublist(0, 20)));
      expect(source.clearCache, throwsA(isA<Exception>()));

      // Chunk 1 has 30 bytes. Make requests with start < progress (30) and end > 60:
      // req1: end = 80 (effectiveEnd 80 > chunk 2's 60 bytes, so it creates _InProgressCacheResponse
      // and completes when chunk 3 arrives)
      final inProgressReq1Future = source.request(10, 80);
      // req2: end = null (end is null, so when chunk 3 arrives it takes the line 228 branch)
      final inProgressReq2Future = source.request(15);
      // outOfBand request: start = 70 (start >= progress)
      final outOfBandReqFuture = source.request(70, 90);

      // Trigger chunk 2 (bytes 30..60 arrive; progress reaches 60, which is < 80)
      slowChunk2Completer!.complete();

      final inProgressResp1 = await inProgressReq1Future;
      final inProgressBytes1 = <int>[];
      final inProgressDone1 = inProgressResp1.stream.forEach(inProgressBytes1.addAll);

      final inProgressResp2 = await inProgressReq2Future;
      final inProgressBytes2 = <int>[];
      final inProgressDone2 = inProgressResp2.stream.forEach(inProgressBytes2.addAll);

      final outOfBandResp = await outOfBandReqFuture;
      expect(await outOfBandResp.stream.first, equals(testData.sublist(70, 90)));

      // Trigger chunk 3 (bytes 60..200 arrive and download finishes; progress reaches 200 >= 80)
      slowChunk3Completer!.complete();

      await inProgressDone1;
      await inProgressDone2;
      expect(inProgressBytes1, equals(testData.sublist(10, 80)));
      expect(inProgressBytes2, equals(testData.sublist(15)));

      while (!cacheFile.existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(cacheFile.existsSync(), isTrue);
    });

    test('error when server returns 500', () async {
      final cacheFile = File('${tempDir.path}/500.mp3');
      final source = LockCachingAudioSource(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server.port}/500.mp3'),
        cacheFile: cacheFile,
      );

      var errorCaught = false;
      await runZonedGuarded(
        () async {
          try {
            await source.request();
          } catch (_) {
            errorCaught = true;
          }
        },
        (_, _) {
          errorCaught = true;
        },
      );
      expect(errorCaught, isTrue);
    });

    test('abort during download deletes partial cache and propagates error', () async {
      final cacheFile = File('${tempDir.path}/abort.mp3');
      final source = LockCachingAudioSource(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server.port}/abort.mp3'),
        cacheFile: cacheFile,
      );

      var errorSeen = false;
      await runZonedGuarded(
        () async {
          try {
            final resp = await source.request(0, 50);
            await resp.stream.drain<void>();
          } catch (_) {
            errorSeen = true;
          }
        },
        (_, _) {
          errorSeen = true;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(errorSeen, isTrue);
      expect(File('${cacheFile.path}.part').existsSync(), isFalse);
    });

    test('error when server returns 404', () async {
      final cacheFile = File('${tempDir.path}/error.mp3');
      final source = LockCachingAudioSource(
        Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${server.port}/404.mp3'),
        cacheFile: cacheFile,
      );

      var errorCaught = false;
      await runZonedGuarded(
        () async {
          try {
            await source.request();
          } catch (e) {
            errorCaught = true;
          }
        },
        (e, st) {
          errorCaught = true;
        },
      );
      expect(errorCaught, isTrue);
    });
  });
}
