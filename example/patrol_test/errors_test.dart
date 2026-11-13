import 'dart:io';

import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'reports a missing file and recovers',
    ($) => withPlayer($, (player) async {
      await expectLater(
        player.setFilePath('${Directory.systemTemp.path}/audio_player_missing.wav').timeout(nativeTimeout),
        throwsA(isA<PlayerException>()),
      );
      expectNear(await player.setAsset(tone).timeout(nativeTimeout), toneDuration);
    }),
  );

  patrolTest(
    'source errors reach errorStream',
    ($) => withPlayer($, (player) async {
      final directory = await Directory.systemTemp.createTemp('audio_player_error_');
      addTearDown(() => directory.delete(recursive: true));
      final errorEvent = expectLater(player.errorStream, emits(isA<PlayerException>())).timeout(nativeTimeout);

      await expectLater(
        player.setFilePath('${directory.path}/missing.mp3').timeout(nativeTimeout),
        throwsA(isA<PlayerException>()),
      );
      await errorEvent;
    }),
  );

  patrolTest(
    'Android source errors include the native code and cause',
    ($) => withPlayer($, (player) async {
      final directory = await Directory.systemTemp.createTemp('audio_player_error_');
      addTearDown(() => directory.delete(recursive: true));
      final errorMatcher = isA<PlayerException>()
          .having((error) => error.code, 'legacy source error type', 0)
          .having((error) => error.message, 'native error code', contains('ERROR_CODE_IO_FILE_NOT_FOUND (2005)'))
          .having((error) => error.message, 'native cause', contains('FileNotFoundException'));
      await expectLater(
        player.setFilePath('${directory.path}/missing.mp3').timeout(nativeTimeout),
        throwsA(errorMatcher),
      );
    }),
    skip: !Platform.isAndroid,
  );

  patrolTest(
    'an unreachable stream fails without hanging',
    ($) => withPlayer($, (player) async {
      await expectLater(
        player.setUrl('http://127.0.0.1:9/none.mp3').timeout(nativeTimeout),
        throwsA(isA<PlayerException>()),
      );
      expectNear(await player.setAsset(tone).timeout(nativeTimeout), toneDuration);
    }),
  );
}
