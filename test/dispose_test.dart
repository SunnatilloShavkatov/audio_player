import 'dart:async';
import 'dart:convert';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:audio_player/src/platform_interface/native_audio_player_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PlaybackEventMessage _readyEvent() => PlaybackEventMessage(
  processingState: ProcessingStateMessage.ready,
  updateTime: DateTime.now(),
  updatePosition: Duration.zero,
  bufferedPosition: Duration.zero,
  duration: const Duration(seconds: 30),
  icyMetadata: null,
  currentIndex: 0,
  androidAudioSessionId: null,
);

/// A native side: it reports every loaded player as ready, and fails the methods listed in [failures].
class _NativeTransport extends NativeAudioPlayerTransport {
  final methods = <String>[];
  final failures = <String, PlatformException>{};

  @override
  Future<String> send(String? playerId, String method, String request) async {
    methods.add(method);
    final failure = failures[method];
    if (failure != null) {
      throw failure;
    }
    if (method == 'load') {
      final ready = jsonEncode({
        'processingState': ProcessingStateMessage.ready.index,
        'updateTime': DateTime.now().millisecondsSinceEpoch,
        'updatePosition': 0,
        'bufferedPosition': 0,
        'duration': 30000000,
        'currentIndex': 0,
      });
      unawaited(Future<void>.delayed(Duration.zero, () => onPlaybackEvent(playerId!, ready)));
    }
    // Swift and Kotlin answer a method they do not handle with "unimplemented".
    if (method == 'dispose') {
      throw PlatformException(code: 'unimplemented', message: 'Unknown method dispose');
    }
    return '{}';
  }

  @override
  void listen() {}
}

/// A platform written before the native players: it has no disposePlayer, only the instance dispose.
class _LegacyPlatform extends AudioPlayerPlatform {
  final disposed = <String>[];

  @override
  Future<AudioPlayerInstancePlatform> init(InitRequest request) async => _LegacyInstance(request.id, disposed);
}

class _LegacyInstance extends AudioPlayerInstancePlatform {
  new(super.id, this._disposed);

  final List<String> _disposed;
  final _events = StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream.empty();

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    Future<void>.delayed(Duration.zero, () => _events.add(_readyEvent()));
    return LoadResponse(duration: const Duration(seconds: 30));
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _disposed.add(id);
    return DisposeResponse();
  }
}

void main() {
  late AudioPlayerPlatform previous;

  setUp(() => previous = AudioPlayerPlatform.instance);
  tearDown(() => AudioPlayerPlatform.instance = previous);

  test('a native disposePlayer failure never triggers a "dispose" call the native side does not handle', () async {
    final transport = _NativeTransport()..failures['disposePlayer'] = PlatformException(code: 'boom');
    AudioPlayerPlatform.instance = NativeAudioPlayerPlatform(transport);
    final player = AudioPlayer();
    await player.setUrl('https://example.com/a.mp3');

    await player.dispose();
    expect(transport.methods, contains('disposePlayer'));
    expect(transport.methods, isNot(contains('dispose')));
  });

  test('a platform without disposePlayer is still disposed through its instance', () async {
    final platform = _LegacyPlatform();
    AudioPlayerPlatform.instance = platform;
    final player = AudioPlayer();
    await player.setUrl('https://example.com/a.mp3');

    await player.dispose();
    expect(platform.disposed, hasLength(1));
  });
}
