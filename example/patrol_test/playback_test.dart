import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'loads an asset and reports its duration',
    ($) => withPlayer($, (player) async {
      expectNear(await player.setAsset(tone).timeout(nativeTimeout), toneDuration);
      expect(player.processingState, ProcessingState.ready);
      expectNear(player.duration, toneDuration);
    }),
  );

  patrolTest(
    'plays, pauses and resumes',
    ($) => withPlayer($, (player) async {
      await player.setAsset(tone).timeout(nativeTimeout);
      final playing = player.play();
      await waitForPosition(player, const Duration(milliseconds: 500));
      await player.pause();
      await playing.timeout(nativeTimeout);
      expect(player.playing, isFalse);
      final pausedAt = player.position;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expectNear(player.position, pausedAt, tolerance: const Duration(milliseconds: 50));

      unawaited(player.play());
      await waitForPosition(player, pausedAt + const Duration(milliseconds: 300));
      await player.pause();
    }),
  );

  patrolTest(
    'play() completes when playback completes',
    ($) => withPlayer($, (player) async {
      await player.setAsset(tone, initialPosition: const Duration(milliseconds: 2500)).timeout(nativeTimeout);
      await player.play().timeout(nativeTimeout);
      expect(player.processingState, ProcessingState.completed);
      expect(player.playing, isTrue);
    }),
  );

  patrolTest(
    'seeks',
    ($) => withPlayer($, (player) async {
      await player.setAsset(tone).timeout(nativeTimeout);
      await player.seek(const Duration(seconds: 2)).timeout(nativeTimeout);
      expectNear(player.position, const Duration(seconds: 2));
      await player.seek(const Duration(milliseconds: 500)).timeout(nativeTimeout);
      expectNear(player.position, const Duration(milliseconds: 500));
    }),
  );

  patrolTest(
    'changes volume and speed while playing',
    ($) => withPlayer($, (player) async {
      await player.setAsset(tone).timeout(nativeTimeout);
      unawaited(player.play());
      await player.setVolume(0.5);
      await player.setSpeed(1.5);
      expect(player.volume, 0.5);
      expect(player.speed, 1.5);
      await waitForPosition(player, const Duration(milliseconds: 500));
      await player.pause();
    }),
  );

  patrolTest(
    'clips',
    ($) => withPlayer($, (player) async {
      await player.setAsset(tone).timeout(nativeTimeout);
      final duration = await player
          .setClip(start: const Duration(milliseconds: 500), end: const Duration(milliseconds: 1500))
          .timeout(nativeTimeout);
      expectNear(duration, const Duration(seconds: 1));
      await player.play().timeout(nativeTimeout);
      expect(player.processingState, ProcessingState.completed);
    }),
  );
}
