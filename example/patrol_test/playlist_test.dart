import 'dart:async';
import 'dart:math';

import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'edits a playlist',
    ($) => withPlayer($, (player) async {
      await player
          .setAudioSources([
            AudioSource.asset(tone, tag: 'a'),
            AudioSource.asset(tone, tag: 'b'),
            AudioSource.asset(tone, tag: 'c'),
          ])
          .timeout(nativeTimeout);
      List<Object?> tags() => player.sequence.map((source) => source.tag).toList();

      expect(player.currentIndex, 0);
      await player.seekToNext();
      await waitForIndex(player, 1);

      await player.addAudioSource(AudioSource.asset(tone, tag: 'd'));
      expect(tags(), ['a', 'b', 'c', 'd']);
      // Moving an item in front of the current one shifts the current index.
      await player.moveAudioSource(3, 0);
      expect(tags(), ['d', 'a', 'b', 'c']);
      await waitForIndex(player, 2);
      await player.removeAudioSourceAt(0);
      expect(tags(), ['a', 'b', 'c']);
      await waitForIndex(player, 1);
      await player.insertAudioSources(0, [AudioSource.asset(tone, tag: 'e'), AudioSource.asset(tone, tag: 'f')]);
      await waitForIndex(player, 3);
      await player.removeAudioSourceRange(0, 2);
      await waitForIndex(player, 1);

      await player.setShuffleModeEnabled(enabled: true);
      await player.shuffle();
      await player.setLoopMode(LoopMode.all);
      expect(player.shuffleModeEnabled, isTrue);
      expect(player.loopMode, LoopMode.all);
      final playing = player.play();
      await waitForPosition(player, const Duration(milliseconds: 300));
      await player.pause();
      await playing.timeout(nativeTimeout);
    }),
  );

  patrolTest(
    'advances gaplessly to the next item',
    ($) => withPlayer($, (player) async {
      await player
          .setAudioSources([AudioSource.asset(tone, tag: 'a'), AudioSource.asset(tone, tag: 'b')])
          .timeout(nativeTimeout);
      await player.seek(const Duration(milliseconds: 2700)).timeout(nativeTimeout);
      unawaited(player.play());
      expect(await player.currentIndexStream.firstWhere((i) => i == 1).timeout(nativeTimeout), 1);
      await player.pause();
    }),
  );

  patrolTest(
    'advances in the current shuffle order',
    ($) => withPlayer($, (player) async {
      await player
          .setAudioSources([
            for (final tag in ['a', 'b', 'c', 'd', 'e']) AudioSource.asset(tone, tag: tag),
          ], shuffleOrder: DefaultShuffleOrder(random: Random(1)))
          .timeout(nativeTimeout);
      await player.setShuffleModeEnabled(enabled: true);
      // Reshuffle until the item after the current one changes, so that the platform player only advances to it if it
      // received the new order.
      final loadedNextIndex = player.nextIndex;
      for (var i = 0; i < 20 && player.nextIndex == loadedNextIndex; i++) {
        await player.shuffle();
      }
      final expectedNextIndex = player.nextIndex;
      expect(expectedNextIndex, isNot(loadedNextIndex));
      final currentIndex = player.currentIndex;
      await player.seek(const Duration(milliseconds: 2700)).timeout(nativeTimeout);
      unawaited(player.play());
      expect(
        await player.currentIndexStream.firstWhere((i) => i != currentIndex).timeout(nativeTimeout),
        expectedNextIndex,
      );
      await player.pause();
    }),
  );

  patrolTest(
    'plays two players at once',
    ($) => withPlayer($, (player) async {
      // On Android every player that handles interruptions asks for the audio focus when it starts, and the other one
      // loses it for good and pauses. A player that does not handle interruptions never asks, so it can play alongside.
      final other = AudioPlayer(handleInterruptions: false);
      addTearDown(other.dispose);
      await player.setAsset(tone).timeout(nativeTimeout);
      await other.setAsset(tone).timeout(nativeTimeout);
      unawaited(player.play());
      unawaited(other.play());
      await Future.wait([
        waitForPosition(player, const Duration(milliseconds: 500)),
        waitForPosition(other, const Duration(milliseconds: 500)),
      ]);
      expect(player.playing, isTrue);
      expect(other.playing, isTrue);
      await player.pause();
      await other.pause();
    }),
  );
}
