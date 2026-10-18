import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidAudioAttributes', () {
    test('default to unknown content type, no flags and unknown usage', () {
      const attributes = AndroidAudioAttributes();
      expect(attributes.contentType, equals(AndroidAudioContentType.unknown));
      expect(attributes.flags, equals(AndroidAudioFlags.none));
      expect(attributes.usage, equals(AndroidAudioUsage.unknown));
    });

    test('compare by value', () {
      const a = AndroidAudioAttributes(contentType: AndroidAudioContentType.music, usage: AndroidAudioUsage.media);
      const b = AndroidAudioAttributes(contentType: AndroidAudioContentType.music, usage: AndroidAudioUsage.media);
      const c = AndroidAudioAttributes(contentType: AndroidAudioContentType.speech, usage: AndroidAudioUsage.media);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(
        const AndroidAudioAttributes(flags: AndroidAudioFlags.audibilityEnforced),
        isNot(equals(const AndroidAudioAttributes())),
      );
    });
  });

  group('AndroidAudioContentType', () {
    test('keeps the order of the Android CONTENT_TYPE constants', () {
      expect(AndroidAudioContentType.values.map((type) => type.index), equals([0, 1, 2, 3, 4]));
      expect(AndroidAudioContentType.speech.index, equals(1));
      expect(AndroidAudioContentType.music.index, equals(2));
    });
  });

  group('AndroidAudioFlags', () {
    test('combine, intersect and test flags', () {
      const other = AndroidAudioFlags(1 << 4);
      final both = AndroidAudioFlags.audibilityEnforced | other;
      expect(both.value, equals(17));
      expect(both.contains(AndroidAudioFlags.audibilityEnforced), isTrue);
      expect(both.contains(other), isTrue);
      expect(AndroidAudioFlags.audibilityEnforced.contains(other), isFalse);
      expect(both & other, equals(other));
      expect(AndroidAudioFlags.none.value, equals(0));
      expect(
        AndroidAudioFlags.audibilityEnforced.hashCode,
        equals(AndroidAudioFlags(AndroidAudioFlags.audibilityEnforced.value).hashCode),
      );
    });
  });

  group('AndroidAudioUsage', () {
    test('matches the Android USAGE constants', () {
      expect(AndroidAudioUsage.unknown.value, equals(0));
      expect(AndroidAudioUsage.media.value, equals(1));
      expect(AndroidAudioUsage.alarm.value, equals(4));
      expect(AndroidAudioUsage.game.value, equals(14));
      expect(AndroidAudioUsage.assistant.value, equals(16));
    });

    test('compare by value', () {
      expect(AndroidAudioUsage.media, equals(AndroidAudioUsage.media));
      expect(AndroidAudioUsage.media.hashCode, equals(AndroidAudioUsage.media.hashCode));
      expect(AndroidAudioUsage.media, isNot(equals(AndroidAudioUsage.game)));
    });
  });
}
