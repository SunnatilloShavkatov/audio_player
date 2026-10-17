import 'package:audio_player/audio_player.dart';
import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AudioPlayerPlatform.instance = SimpleMockAudioPlayerPlatform();

  group('AudioSource types and methods', () {
    test('AudioSource.file constructor', () {
      final fileSource = AudioSource.file('/path/to/audio.mp3', tag: 'file_tag');
      expect(fileSource.uri, equals(Uri.file('/path/to/audio.mp3')));
      expect(fileSource.tag, equals('file_tag'));
    });

    test('SilenceAudioSource duration, tag, and mutation', () async {
      final silence = SilenceAudioSource(duration: const Duration(seconds: 5), tag: 'silence');
      expect(silence.duration, equals(const Duration(seconds: 5)));
      expect(silence.tag, equals('silence'));

      silence.duration = const Duration(seconds: 10);
      expect(silence.duration, equals(const Duration(seconds: 10)));
      expect(silence.sequence, equals([silence]));
      expect(silence.shuffleIndices, equals([0]));

      final player = AudioPlayer();
      await player.setAudioSource(silence);
      await player.dispose();
    });

    test('Dash and Hls audio sources serialization', () async {
      final dash = DashAudioSource(
        Uri.parse('https://example.com/manifest.mpd'),
        headers: {'dash_h': 'val'},
        tag: 'dash_tag',
      );
      final hls = HlsAudioSource(
        Uri.parse('https://example.com/playlist.m3u8'),
        headers: {'hls_h': 'val'},
        tag: 'hls_tag',
      );

      final player = AudioPlayer();
      await player.setAudioSources([dash, hls]);
      expect(player.sequence, containsAll([dash, hls]));
      await player.dispose();
    });

    test('AudioSource equality and hashCode', () {
      final s1 = AudioSource.uri(Uri.parse('https://example.com/1.mp3'));
      final s2 = AudioSource.uri(Uri.parse('https://example.com/2.mp3'));

      expect(s1, equals(s1));
      expect(s1.hashCode, equals(s1.hashCode));
      expect(s1, isNot(equals(s2)));
    });

    test('ClippingAudioSource properties', () async {
      final child = AudioSource.uri(Uri.parse('https://example.com/clip.mp3'));
      final clipping = ClippingAudioSource(
        child: child,
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 5),
        tag: 'clip_tag',
      );
      expect(clipping.tag, equals('clip_tag'));
      expect(clipping.start, equals(const Duration(seconds: 1)));
      expect(clipping.end, equals(const Duration(seconds: 5)));

      final player = AudioPlayer();
      await player.setAudioSource(clipping);
      await player.dispose();
    });

    test('AudioPlayer setFilePath', () async {
      final player = AudioPlayer();
      await player.setFilePath('/tmp/test.mp3', preload: false);
      expect(player.audioSources.length, equals(1));
      await player.dispose();
    });

    test('AudioPlayer setClip throws a StateError if playlist does not contain 1 UriAudioSource', () async {
      final player = AudioPlayer();
      expect(player.setClip, throwsStateError);
      await player.dispose();
    });

    test('AudioPlayer audioSources getter', () async {
      final player = AudioPlayer();
      expect(player.audioSources, isEmpty);
      await player.dispose();
    });
  });
}
