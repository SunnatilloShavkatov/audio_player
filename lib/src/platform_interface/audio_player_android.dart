import 'dart:async';

import 'package:audio_player/src/bindings/audio_player_api.g.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:audio_player/src/platform_interface/native_audio_player_platform.dart';
import 'package:flutter/services.dart';
import 'package:jni/jni.dart';

/// [NativeAudioPlayerTransport] over JNI: Dart calls `AudioPlayerApi` directly, with no method channel. Every
/// callback is asynchronous, so Kotlin never blocks on Dart.
///
/// Replies come back through one [AudioPlayerApi$ResultCallback] per isolate, matched to their call by a call id,
/// instead of a proxy (and a receive port that only closes when Java collects it) per call.
class AndroidAudioPlayerTransport extends NativeAudioPlayerTransport {
  final _pending = <int, Completer<String>>{};
  int _nextCallId = 0;
  AudioPlayerApi$ResultCallback? _results;

  /// Lives as long as the isolate: Kotlin keeps it only while a call is pending.
  AudioPlayerApi$ResultCallback get _resultCallback => _results ??= AudioPlayerApi$ResultCallback.implement(
    $AudioPlayerApi$ResultCallback(
      onResult: (int callId, JString? json) {
        final text = json?.toDartString(releaseOriginal: true) ?? '{}';
        _pending.remove(callId)?.complete(text);
      },
      onResult$async: true,
      onError: (int callId, JString? code, JString? message, JString? details) {
        final error = NativeAudioPlayerTransport.platformException(
          code?.toDartString(releaseOriginal: true) ?? 'error',
          message?.toDartString(releaseOriginal: true),
          details?.toDartString(releaseOriginal: true),
        );
        _pending.remove(callId)?.completeError(error);
      },
      onError$async: true,
    ),
  );

  @override
  Future<String> send(String? playerId, String method, String request) {
    final callId = _nextCallId++;
    final completer = Completer<String>();
    _pending[callId] = completer;
    try {
      final callback = _resultCallback;
      using((arena) {
        final jMethod = method.toJString()..releasedBy(arena);
        final jRequest = request.toJString()..releasedBy(arena);
        if (playerId == null) {
          AudioPlayerApi.call(engineId, callId, jMethod, jRequest, callback);
        } else {
          final jPlayerId = playerId.toJString()..releasedBy(arena);
          AudioPlayerApi.callPlayer(engineId, callId, jPlayerId, jMethod, jRequest, callback);
        }
      });
    } on Object catch (e) {
      // Any synchronous failure (a Java exception, a JNI error) becomes a failed future, never a throw.
      _pending.remove(callId);
      return Future<String>.error(e is PlatformException ? e : PlatformException(code: 'error', message: '$e'));
    }
    return completer.future;
  }

  @override
  void listen() {
    final listener = AudioPlayerApi$PlaybackListener.implement(
      $AudioPlayerApi$PlaybackListener(
        onPlaybackEvent: (JString? playerId, JString? json) {
          if (playerId != null && json != null) {
            onPlaybackEvent(playerId.toDartString(releaseOriginal: true), json.toDartString(releaseOriginal: true));
          }
        },
        onPlaybackEvent$async: true,
        onPlayerData: (JString? playerId, JString? json) {
          if (playerId != null && json != null) {
            onPlayerData(playerId.toDartString(releaseOriginal: true), json.toDartString(releaseOriginal: true));
          }
        },
        onPlayerData$async: true,
        onPlaybackError: (JString? playerId, JString? code, JString? message, JString? details) {
          if (playerId != null) {
            onPlaybackError(
              playerId.toDartString(releaseOriginal: true),
              code?.toDartString(releaseOriginal: true) ?? 'error',
              message?.toDartString(releaseOriginal: true),
              details?.toDartString(releaseOriginal: true),
            );
          }
        },
        onPlaybackError$async: true,
      ),
    );
    handOver(listener, (proxy) {
      using((arena) {
        AudioPlayerApi.setPlaybackListener(engineId, listenerId.toJString()..releasedBy(arena), proxy);
      });
    });
  }
}

/// Passes a Dart-implemented JNI [proxy] to Kotlin and releases Dart's own reference afterwards: Kotlin holds its
/// own, and the port closes once Java collects the proxy. Without it the proxy pins a global ref until Dart GC.
void handOver<T extends JObject>(T proxy, void Function(T proxy) pass) {
  try {
    pass(proxy);
  } finally {
    proxy.release();
  }
}

/// The [AudioPlayerPlatform] used on Android.
class AndroidAudioPlayerPlatform extends NativeAudioPlayerPlatform {
  new() : super(AndroidAudioPlayerTransport());
}
