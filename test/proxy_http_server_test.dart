import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_platform.dart';

class _HttpOverrides extends HttpOverrides;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _HttpOverrides();
  AudioPlayerPlatform.instance = SimpleMockAudioPlayerPlatform();

  group('ProxyHttpServer with m3u8 playlist', () {
    late HttpServer originServer;

    setUp(() async {
      originServer = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
        ..listen((request) async {
          if (request.uri.path == '/redirect') {
            await request.response.redirect(
              Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${originServer.port}/final'),
            );
            return;
          }
          if (request.uri.path == '/final') {
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg')
              ..write('redirected_data');
            await request.response.close();
            return;
          }
          if (request.uri.path.endsWith('.m3u8')) {
            const m3u8Content = '''

#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10,
segment1.ts
#EXTINF:10,
http://other.com/segment2.ts
''';
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl')
              ..write(m3u8Content);
            await request.response.close();
            return;
          }

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.contentTypeHeader, 'video/MP2T')
            ..write('segment_data');
          await request.response.close();
        });
    });

    tearDown(() async {
      await originServer.close(force: true);
    });

    test('m3u8 parsing and nested resource registration', () async {
      final player = AudioPlayer();
      final uri = Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${originServer.port}/playlist.m3u8',
      );
      final headers = {'X-Test-Auth': 'Bearer test'};
      await player.setUrl('$uri', headers: headers);

      final proxyUrl = Uri.parse(player.icyMetadata!.info!.url!);
      final client = HttpClient();
      final req = await client.getUrl(proxyUrl);
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      final body = await resp.transform(utf8.decoder).join();
      expect(body, contains('segment1.ts'));

      client.close();
      await player.dispose();
    });

    test('proxy server follows origin redirects', () async {
      final player = AudioPlayer();
      final uri = Uri.parse('http://${InternetAddress.loopbackIPv4.address}:${originServer.port}/redirect');
      final headers = {'X-Test-Auth': 'Bearer test'};
      await player.setUrl('$uri', headers: headers);

      final proxyUrl = Uri.parse(player.icyMetadata!.info!.url!);
      final client = HttpClient();
      final req = await client.getUrl(proxyUrl);
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      final body = await resp.transform(utf8.decoder).join();
      expect(body, equals('redirected_data'));

      client.close();
      await player.dispose();
    });
  });

  group('IdleAudioPlayer extra tests', () {
    test('audio effects in idle state', () async {
      final equalizer = AndroidEqualizer();
      final enhancer = AndroidLoudnessEnhancer();
      final player = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, enhancer]),
      );

      await equalizer.setEnabled(enabled: true);
      expect(equalizer.enabled, isTrue);

      await enhancer.setEnabled(enabled: true);
      expect(enhancer.enabled, isTrue);
      await enhancer.setTargetGain(1.2);
      expect(enhancer.targetGain, equals(1.2));

      // In idle state, _activate is never called so the parameters completer
      // is never completed. Verify the future stays pending rather than
      // awaiting it (which would timeout).
      var parametersCompleted = false;
      unawaited(equalizer.parameters.then((_) => parametersCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(parametersCompleted, isFalse);

      await player.dispose();
    });

    test('StreamAudioSource error returns 500 and removeStreamAudioSource cleans up', () async {
      final player = AudioPlayer();
      final failingSource = _FailingStreamAudioSource();
      // Use preload: true so the platform is activated and icyMetadata is set.
      await player.setAudioSources([failingSource]);

      final proxyUri = Uri.parse(player.icyMetadata!.info!.url!);
      final client = HttpClient();
      final req = await client.getUrl(proxyUri);
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.internalServerError));
      client.close();

      await player.clearAudioSources();
      await player.dispose();
    });
  });
}

class _FailingStreamAudioSource extends StreamAudioSource {
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) {
    throw Exception('Simulated proxy failure');
  }
}
