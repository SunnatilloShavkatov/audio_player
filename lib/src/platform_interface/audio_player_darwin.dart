import 'dart:async';

import 'package:audio_player/src/bindings/audio_player_darwin.g.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:audio_player/src/platform_interface/native_audio_player_platform.dart';
import 'package:flutter/services.dart';
import 'package:objective_c/objective_c.dart' as objc;

/// [NativeAudioPlayerTransport] over the Objective-C runtime: Dart calls `AudioPlayerApi` (Swift, `@objc`)
/// directly, with no method channel. Results and events are listener blocks, which may fire on any thread and are
/// delivered to this isolate.
class DarwinAudioPlayerTransport extends NativeAudioPlayerTransport {
  @override
  Future<String> send(String? playerId, String method, String request) {
    final completer = Completer<String>();
    try {
      final callback = ObjCBlock_ffiVoid_NSString_NSString_NSString_NSString$1.listener((
        objc.NSString? json,
        objc.NSString? code,
        objc.NSString? message,
        objc.NSString? details,
      ) {
        if (completer.isCompleted) {
          return;
        }
        if (code == null) {
          completer.complete(json?.toDartString() ?? '{}');
        } else {
          completer.completeError(
            NativeAudioPlayerTransport.platformException(
              code.toDartString(),
              message?.toDartString(),
              details?.toDartString(),
            ),
          );
        }
      });
      if (playerId == null) {
        AudioPlayerApi.callMain(method.toNSString(), request: request.toNSString(), callback: callback);
      } else {
        AudioPlayerApi.callPlayer(
          playerId.toNSString(),
          method: method.toNSString(),
          request: request.toNSString(),
          callback: callback,
        );
      }
    } on Object catch (e) {
      return Future<String>.error(PlatformException(code: 'error', message: '$e'));
    }
    return completer.future;
  }

  @override
  void listen() {
    AudioPlayerApi.setPlaybackListenersWithPlaybackEvent(
      ObjCBlock_ffiVoid_NSString_NSString.listener(
        (objc.NSString playerId, objc.NSString json) => onPlaybackEvent(playerId.toDartString(), json.toDartString()),
      ),
      playerData: ObjCBlock_ffiVoid_NSString_NSString.listener(
        (objc.NSString playerId, objc.NSString json) => onPlayerData(playerId.toDartString(), json.toDartString()),
      ),
      playbackError: ObjCBlock_ffiVoid_NSString_NSString_NSString_NSString.listener(
        (objc.NSString playerId, objc.NSString code, objc.NSString? message, objc.NSString? details) => onPlaybackError(
          playerId.toDartString(),
          code.toDartString(),
          message?.toDartString(),
          details?.toDartString(),
        ),
      ),
    );
  }
}

/// The [AudioPlayerPlatform] used on iOS and macOS.
class DarwinAudioPlayerPlatform extends NativeAudioPlayerPlatform {
  new() : super(DarwinAudioPlayerTransport());
}
