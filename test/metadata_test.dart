import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IcyMetadata', () {
    test('IcyInfo equality, hashCode and toString', () {
      const info1 = IcyInfo(title: 'Song Title', url: 'https://example.com/stream');
      const info2 = IcyInfo(title: 'Song Title', url: 'https://example.com/stream');
      const info3 = IcyInfo(title: 'Other Title', url: 'https://example.com/stream');

      expect(info1, equals(info2));
      expect(info1.hashCode, equals(info2.hashCode));
      expect(info1, isNot(equals(info3)));
      expect(info1.toString(), equals('title=Song Title,url=https://example.com/stream'));
    });

    test('IcyHeaders equality, hashCode and toString', () {
      const h1 = IcyHeaders(
        bitrate: 128,
        genre: 'Rock',
        name: 'Rock FM',
        metadataInterval: 8192,
        url: 'https://rock.fm',
        isPublic: true,
      );
      const h2 = IcyHeaders(
        bitrate: 128,
        genre: 'Rock',
        name: 'Rock FM',
        metadataInterval: 8192,
        url: 'https://rock.fm',
        isPublic: true,
      );
      const h3 = IcyHeaders(
        bitrate: 256,
        genre: 'Jazz',
        name: 'Jazz FM',
        metadataInterval: 4096,
        url: 'https://jazz.fm',
        isPublic: false,
      );

      expect(h1, equals(h2));
      expect(h1.hashCode, equals(h2.hashCode));
      expect(h1, isNot(equals(h3)));
      expect(
        h1.toString(),
        equals('bitrate=128,genre=Rock,name=Rock FM,metadataInterval=8192,url=https://rock.fm,isPublic=true'),
      );
    });

    test('IcyMetadata equality, hashCode and structure', () {
      const info = IcyInfo(title: 'Song', url: 'https://url');
      const headers = IcyHeaders(
        bitrate: 128,
        genre: 'Pop',
        name: 'Pop Station',
        metadataInterval: 1024,
        url: 'https://pop.station',
        isPublic: true,
      );

      const meta1 = IcyMetadata(info: info, headers: headers);
      const meta2 = IcyMetadata(info: info, headers: headers);
      const meta3 = IcyMetadata(info: null, headers: null);

      expect(meta1, equals(meta2));
      expect(meta1.hashCode, equals(meta2.hashCode));
      expect(meta1, isNot(equals(meta3)));
      expect(meta1.info, equals(info));
      expect(meta1.headers, equals(headers));
    });
  });
}
