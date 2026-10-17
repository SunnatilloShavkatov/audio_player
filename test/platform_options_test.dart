import 'package:audio_player/audio_player.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioPlayerPlatform.instance = SimpleMockAudioPlayerPlatform();

  group('PlayerException', () {
    test('constructors and toString', () {
      final ex = PlayerException(404, 'Not Found', 1);
      expect(ex.code, equals(404));
      expect(ex.message, equals('Not Found'));
      expect(ex.index, equals(1));
      expect(ex.toString(), equals('(404) Not Found'));
    });

    test('PlayerInterruptedException', () {
      final ex = PlayerInterruptedException('Interrupted by load');
      expect(ex.message, equals('Interrupted by load'));
      expect(ex.toString(), equals('Interrupted by load'));
    });
  });

  group('Platform options', () {
    test('ProgressiveAudioSourceOptions and its children', () async {
      const darwinOptions = DarwinAssetOptions(preferPreciseDurationAndTiming: true);
      expect(darwinOptions.preferPreciseDurationAndTiming, isTrue);

      const androidOptions = AndroidExtractorOptions(
        constantBitrateSeekingEnabled: false,
        constantBitrateSeekingAlwaysEnabled: true,
        mp3Flags: AndroidExtractorOptions.flagMp3EnableIndexSeeking | AndroidExtractorOptions.flagMp3DisableId3Metadata,
      );
      expect(androidOptions.constantBitrateSeekingEnabled, isFalse);
      expect(androidOptions.constantBitrateSeekingAlwaysEnabled, isTrue);
      expect(
        androidOptions.mp3Flags,
        equals(AndroidExtractorOptions.flagMp3EnableIndexSeeking | AndroidExtractorOptions.flagMp3DisableId3Metadata),
      );

      const sourceOptions = ProgressiveAudioSourceOptions(
        darwinAssetOptions: darwinOptions,
        androidExtractorOptions: androidOptions,
      );
      expect(sourceOptions.darwinAssetOptions, equals(darwinOptions));
      expect(sourceOptions.androidExtractorOptions, equals(androidOptions));

      final source = ProgressiveAudioSource(Uri.parse('https://example.com/audio.mp3'), options: sourceOptions);
      final player = AudioPlayer();
      await player.setAudioSource(source);
      expect(player.audioSource, equals(source));
      await player.dispose();
    });
  });
}
