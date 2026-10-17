import 'package:audio_player/audio_player.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioPlayerPlatform.instance = SimpleMockAudioPlayerPlatform();

  group('AudioLoadConfiguration', () {
    test('construction and _toMessage via AudioPlayer init', () async {
      const darwinLoadControl = DarwinLoadControl(
        automaticallyWaitsToMinimizeStalling: false,
        preferredForwardBufferDuration: Duration(seconds: 15),
        canUseNetworkResourcesForLiveStreamingWhilePaused: true,
        preferredPeakBitRate: 500000,
      );
      expect(darwinLoadControl.automaticallyWaitsToMinimizeStalling, isFalse);
      expect(darwinLoadControl.preferredForwardBufferDuration, equals(const Duration(seconds: 15)));
      expect(darwinLoadControl.canUseNetworkResourcesForLiveStreamingWhilePaused, isTrue);
      expect(darwinLoadControl.preferredPeakBitRate, equals(500000));

      const androidLoadControl = AndroidLoadControl(
        minBufferDuration: Duration(seconds: 20),
        maxBufferDuration: Duration(seconds: 40),
        bufferForPlaybackDuration: Duration(milliseconds: 1500),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
        targetBufferBytes: 1024 * 1024,
        prioritizeTimeOverSizeThresholds: true,
        backBufferDuration: Duration(seconds: 10),
      );
      expect(androidLoadControl.minBufferDuration, equals(const Duration(seconds: 20)));
      expect(androidLoadControl.maxBufferDuration, equals(const Duration(seconds: 40)));
      expect(androidLoadControl.bufferForPlaybackDuration, equals(const Duration(milliseconds: 1500)));
      expect(androidLoadControl.bufferForPlaybackAfterRebufferDuration, equals(const Duration(seconds: 3)));
      expect(androidLoadControl.targetBufferBytes, equals(1024 * 1024));
      expect(androidLoadControl.prioritizeTimeOverSizeThresholds, isTrue);
      expect(androidLoadControl.backBufferDuration, equals(const Duration(seconds: 10)));

      const speedControl = AndroidLivePlaybackSpeedControl(
        fallbackMinPlaybackSpeed: 0.95,
        fallbackMaxPlaybackSpeed: 1.05,
        minUpdateInterval: Duration(milliseconds: 500),
        proportionalControlFactor: 0.8,
        maxLiveOffsetErrorForUnitSpeed: Duration(milliseconds: 30),
        targetLiveOffsetIncrementOnRebuffer: Duration(milliseconds: 400),
        minPossibleLiveOffsetSmoothingFactor: 0.95,
      );
      expect(speedControl.fallbackMinPlaybackSpeed, equals(0.95));
      expect(speedControl.fallbackMaxPlaybackSpeed, equals(1.05));
      expect(speedControl.minUpdateInterval, equals(const Duration(milliseconds: 500)));
      expect(speedControl.proportionalControlFactor, equals(0.8));
      expect(speedControl.maxLiveOffsetErrorForUnitSpeed, equals(const Duration(milliseconds: 30)));
      expect(speedControl.targetLiveOffsetIncrementOnRebuffer, equals(const Duration(milliseconds: 400)));
      expect(speedControl.minPossibleLiveOffsetSmoothingFactor, equals(0.95));

      const offloadPrefs = AndroidAudioOffloadPreferences(
        audioOffloadMode: AndroidAudioOffloadMode.enabled,
        isGaplessSupportRequired: true,
        isSpeedChangeSupportRequired: true,
      );
      expect(offloadPrefs.audioOffloadMode, equals(AndroidAudioOffloadMode.enabled));
      expect(offloadPrefs.isGaplessSupportRequired, isTrue);
      expect(offloadPrefs.isSpeedChangeSupportRequired, isTrue);

      const config = AudioLoadConfiguration(
        darwinLoadControl: darwinLoadControl,
        androidLoadControl: androidLoadControl,
        androidLivePlaybackSpeedControl: speedControl,
      );
      expect(config.darwinLoadControl, equals(darwinLoadControl));
      expect(config.androidLoadControl, equals(androidLoadControl));
      expect(config.androidLivePlaybackSpeedControl, equals(speedControl));

      final player = AudioPlayer(audioLoadConfiguration: config, androidAudioOffloadPreferences: offloadPrefs);
      await player.setAudioSource(AudioSource.uri(Uri.parse('https://example.com/audio.mp3')));
      await player.dispose();
    });

    test('non-const constructor coverage', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final d = DarwinLoadControl(automaticallyWaitsToMinimizeStalling: now > 0);
      final a = AndroidLoadControl(prioritizeTimeOverSizeThresholds: now < 0);
      final s = AndroidLivePlaybackSpeedControl(fallbackMinPlaybackSpeed: now > 0 ? 0.97 : 0);
      final o = AndroidAudioOffloadPreferences(isGaplessSupportRequired: now < 0);
      final c = AudioLoadConfiguration(darwinLoadControl: d);

      expect(d.automaticallyWaitsToMinimizeStalling, isTrue);
      expect(a.prioritizeTimeOverSizeThresholds, isFalse);
      expect(s.fallbackMinPlaybackSpeed, equals(0.97));
      expect(o.isGaplessSupportRequired, isFalse);
      expect(c.darwinLoadControl, equals(d));
    });
  });
}
