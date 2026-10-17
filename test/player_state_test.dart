import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerEvent', () {
    test('equality, hashCode, copyWith and toString', () {
      final now = DateTime.now();
      final pbEvent1 = PlaybackEvent(
        processingState: ProcessingState.ready,
        updateTime: now,
        updatePosition: const Duration(seconds: 1),
        bufferedPosition: const Duration(seconds: 2),
        duration: const Duration(seconds: 10),
        currentIndex: 0,
        androidAudioSessionId: 42,
        errorCode: 100,
        errorMessage: 'err',
      );
      final event1 = PlayerEvent(playbackEvent: pbEvent1, playing: true);
      final event2 = PlayerEvent(playbackEvent: pbEvent1, playing: true);
      final event3 = event1.copyWith(playing: false);

      expect(event1, equals(event2));
      expect(event1.hashCode, equals(event2.hashCode));
      expect(event1, isNot(equals(event3)));
      expect(event1.toString(), contains('playing=true'));
      expect(event3.playing, isFalse);
      expect(event3.playbackEvent, equals(pbEvent1));

      final defaultEvent = PlayerEvent();
      expect(defaultEvent.playing, isFalse);
      expect(defaultEvent.playbackEvent.processingState, equals(ProcessingState.idle));
    });
  });

  group('PlaybackEvent', () {
    test('equality, hashCode, copyWith and toString', () {
      final time = DateTime(2025);
      final pb1 = PlaybackEvent(
        processingState: ProcessingState.buffering,
        updateTime: time,
        updatePosition: const Duration(seconds: 5),
        bufferedPosition: const Duration(seconds: 6),
        duration: const Duration(seconds: 30),
        currentIndex: 1,
        androidAudioSessionId: 10,
        errorCode: 1,
        errorMessage: 'error',
      );

      final pb2 = PlaybackEvent(
        processingState: ProcessingState.buffering,
        updateTime: time,
        updatePosition: const Duration(seconds: 5),
        bufferedPosition: const Duration(seconds: 6),
        duration: const Duration(seconds: 30),
        currentIndex: 1,
        androidAudioSessionId: 10,
        errorCode: 1,
        errorMessage: 'error',
      );

      expect(pb1, equals(pb2));
      expect(pb1.hashCode, equals(pb2.hashCode));
      expect(pb1.toString(), contains('buffering'));

      final pb3 = pb1.copyWith(
        processingState: ProcessingState.ready,
        updateTime: DateTime(2025, 1, 2),
        updatePosition: const Duration(seconds: 10),
        bufferedPosition: const Duration(seconds: 12),
        duration: const Duration(seconds: 40),
        currentIndex: 2,
        androidAudioSessionId: 20,
        errorCode: 2,
        errorMessage: 'err2',
      );

      expect(pb3.processingState, equals(ProcessingState.ready));
      expect(pb3.updatePosition, equals(const Duration(seconds: 10)));
      expect(pb3.bufferedPosition, equals(const Duration(seconds: 12)));
      expect(pb3.duration, equals(const Duration(seconds: 40)));
      expect(pb3.currentIndex, equals(2));
      expect(pb3.androidAudioSessionId, equals(20));
      expect(pb3.errorCode, equals(2));
      expect(pb3.errorMessage, equals('err2'));

      final pbEmptyCopy = pb1.copyWith();
      expect(pbEmptyCopy, equals(pb1));
      expect(pbEmptyCopy.updatePosition, equals(pb1.updatePosition));
      expect(pb1, isNot(equals(pb3)));
    });
  });

  group('PlayerState', () {
    test('equality, hashCode and toString', () {
      const state1 = PlayerState(playing: true, processingState: ProcessingState.ready);
      const state2 = PlayerState(playing: true, processingState: ProcessingState.ready);
      const state3 = PlayerState(playing: false, processingState: ProcessingState.ready);
      const state4 = PlayerState(playing: true, processingState: ProcessingState.idle);

      expect(state1, equals(state2));
      expect(state1.hashCode, equals(state2.hashCode));
      expect(state1, isNot(equals(state3)));
      expect(state1, isNot(equals(state4)));
      expect(state1.toString(), equals('playing=true,processingState=ProcessingState.ready'));
    });
  });

  group('Enums', () {
    test('LoopMode and ProcessingState values', () {
      expect(LoopMode.values, containsAll([LoopMode.off, LoopMode.one, LoopMode.all]));
      expect(
        ProcessingState.values,
        containsAll([
          ProcessingState.idle,
          ProcessingState.loading,
          ProcessingState.buffering,
          ProcessingState.ready,
          ProcessingState.completed,
        ]),
      );
    });
  });
}
