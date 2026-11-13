import 'dart:async';
import 'dart:io';

import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'common.dart';

void main() {
  patrolTest(
    'stops, releasing the native player, and reloads',
    ($) => withPlayer($, (player) async {
      await player.setAsset(tone).timeout(nativeTimeout);
      await player.seek(const Duration(seconds: 1)).timeout(nativeTimeout);
      await player.stop();
      expect(player.processingState, ProcessingState.idle);
      expectNear(await player.load().timeout(nativeTimeout), toneDuration);
      expectNear(player.position, const Duration(seconds: 1));
    }),
  );

  patrolTest('disposes a player and creates a new one', ($) async {
    await pumpHost($);
    final first = AudioPlayer();
    await first.setAsset(tone).timeout(nativeTimeout);
    unawaited(first.play());
    await waitForPosition(first, const Duration(milliseconds: 300));
    await first.dispose().timeout(nativeTimeout);

    final second = AudioPlayer();
    addTearDown(second.dispose);
    expectNear(await second.setAsset(tone).timeout(nativeTimeout), toneDuration);
    final playing = second.play();
    await waitForPosition(second, const Duration(milliseconds: 300));
    expect(second.playing, isTrue);
    await second.pause();
    await playing.timeout(nativeTimeout);
  });

  patrolTest(
    'releases the platform players of disposed players that were playing',
    ($) => withPlayer($, (player) async {
      // Each of these registers audio session observers (iOS) or holds the audio focus (Android) while it plays. If
      // disposing did not release them, a later player could not play, or a notification would reach a dead player.
      for (var i = 0; i < 3; i++) {
        final playing = AudioPlayer();
        await playing.setAsset(tone).timeout(nativeTimeout);
        unawaited(playing.play());
        await waitForPosition(playing, const Duration(milliseconds: 200));
        await playing.dispose().timeout(nativeTimeout);
      }
      await player.setAsset(tone).timeout(nativeTimeout);
      unawaited(player.play());
      await waitForPosition(player, const Duration(milliseconds: 300));
      expect(player.playing, isTrue);
      await player.pause();
    }),
  );

  patrolTest('plays with interruption and audio session handling turned off', ($) async {
    await pumpHost($);
    final manual = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
    addTearDown(manual.dispose);
    expect(manual.handleInterruptions, isFalse);
    expect(manual.handleAudioSessionActivation, isFalse);
    expectNear(
      await manual.setAsset(tone, initialPosition: const Duration(milliseconds: 2500)).timeout(nativeTimeout),
      toneDuration,
    );
    await manual.play().timeout(nativeTimeout);
    expect(manual.processingState, ProcessingState.completed);
  });

  patrolTest(
    'applies Android audio attributes, and ignores them elsewhere',
    ($) => withPlayer($, (player) async {
      // Set before the source is loaded, so that the native player applies them once it has prepared.
      await player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(contentType: AndroidAudioContentType.music, usage: AndroidAudioUsage.media),
      );
      expectNear(await player.setAsset(tone).timeout(nativeTimeout), toneDuration);
      if (Platform.isAndroid) {
        expect(player.androidAudioSessionId, isNotNull);
      }
      // And again while the source is loaded.
      await player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.assistanceNavigationGuidance,
        ),
      );
      final playing = player.play();
      await waitForPosition(player, const Duration(milliseconds: 300));
      expect(player.playing, isTrue);
      await player.pause();
      await playing.timeout(nativeTimeout);
    }),
  );

  patrolTest(
    'pauses when another player takes the audio focus on Android',
    ($) => withPlayer($, (player) async {
      final other = AudioPlayer();
      addTearDown(other.dispose);
      await player.setAsset(tone).timeout(nativeTimeout);
      await other.setAsset(tone).timeout(nativeTimeout);
      final playing = player.play();
      await waitForPosition(player, const Duration(milliseconds: 300));

      unawaited(other.play());
      // ExoPlayer pauses itself on a permanent loss of the focus, so the native player has to report `playing: false`
      // (a data event through the callback listener) and answer the pending play() request.
      await player.playingStream.firstWhere((isPlaying) => !isPlaying).timeout(nativeTimeout);
      await playing.timeout(nativeTimeout);
      expect(player.playing, isFalse);
      expect(other.playing, isTrue);
      await waitForPosition(other, const Duration(milliseconds: 300));

      // Asking for the focus back works, and takes it from the other player in turn.
      unawaited(player.play());
      await other.playingStream.firstWhere((isPlaying) => !isPlaying).timeout(nativeTimeout);
      expect(player.playing, isTrue);
      await player.pause();
    }),
    skip: !Platform.isAndroid,
  );

  patrolTest('applies Android audio effects, and ignores them elsewhere', ($) async {
    await pumpHost($);
    final equalizer = AndroidEqualizer();
    final loudnessEnhancer = AndroidLoudnessEnhancer();
    final effectsPlayer = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, loudnessEnhancer]));
    addTearDown(effectsPlayer.dispose);
    expectNear(await effectsPlayer.setAsset(tone).timeout(nativeTimeout), toneDuration);
    await equalizer.setEnabled(enabled: true);
    await loudnessEnhancer.setEnabled(enabled: true);
    await loudnessEnhancer.setTargetGain(0.5);
    if (Platform.isAndroid) {
      final parameters = await equalizer.parameters.timeout(nativeTimeout);
      expect(parameters.bands, isNotEmpty);
      await parameters.bands.first.setGain(parameters.minDecibels);
    }
    final playing = effectsPlayer.play();
    await waitForPosition(effectsPlayer, const Duration(milliseconds: 300));
    await effectsPlayer.pause();
    await playing.timeout(nativeTimeout);
  });
}
