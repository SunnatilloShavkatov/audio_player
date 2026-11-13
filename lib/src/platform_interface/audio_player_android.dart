import 'dart:async';

import 'package:audio_player/src/bindings/audio_player_api.g.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:audio_player/src/platform_interface/native_audio_player_platform.dart';
import 'package:flutter/services.dart';
import 'package:jni/jni.dart';

/// [NativeAudioPlayerTransport] over JNI: Dart calls `AudioPlayerApi` directly, with no method channel. Every
/// callback is asynchronous, so Kotlin never blocks on Dart.
class AndroidAudioPlayerTransport extends NativeAudioPlayerTransport {
  @override
  Future<String> send(String? playerId, String method, String request) {
    final completer = Completer<String>();
    try {
      final callback = AudioPlayerApi$ResultCallback.implement(
        $AudioPlayerApi$ResultCallback(
          onResult: (JString? json) {
            final text = json?.toDartString(releaseOriginal: true) ?? '{}';
            if (!completer.isCompleted) {
              completer.complete(text);
            }
          },
          onResult$async: true,
          onError: (JString? code, JString? message, JString? details) {
            final error = NativeAudioPlayerTransport.platformException(
              code?.toDartString(releaseOriginal: true) ?? 'error',
              message?.toDartString(releaseOriginal: true),
              details?.toDartString(releaseOriginal: true),
            );
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
          onError$async: true,
        ),
      );
      using((arena) {
        final jMethod = method.toJString()..releasedBy(arena);
        final jRequest = request.toJString()..releasedBy(arena);
        if (playerId == null) {
          AudioPlayerApi.call(jMethod, jRequest, callback);
        } else {
          AudioPlayerApi.callPlayer(playerId.toJString()..releasedBy(arena), jMethod, jRequest, callback);
        }
      });
    } on JThrowable catch (e) {
      return Future<String>.error(PlatformException(code: 'error', message: e.toString()));
    }
    return completer.future;
  }

  @override
  void listen() {
    AudioPlayerApi.playbackListener = AudioPlayerApi$PlaybackListener.implement(
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
  }
}

/// The [AudioPlayerPlatform] used on Android.
class AndroidAudioPlayerPlatform extends NativeAudioPlayerPlatform {
  new() : super(AndroidAudioPlayerTransport());
}
