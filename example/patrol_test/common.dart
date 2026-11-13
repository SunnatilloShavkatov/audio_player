import 'package:audio_player/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:patrol/patrol.dart';

/// The bundled 3 second tone, so the tests need no network access.
const tone = 'assets/audio/tone.wav';
const toneDuration = Duration(seconds: 3);

/// How long to wait for the native player before failing a test.
const nativeTimeout = Duration(seconds: 15);

/// Pumps a blank app, so the test runs inside a real, foreground Flutter activity.
Future<void> pumpHost(PatrolIntegrationTester $) => $.pumpWidget(const MaterialApp(home: Scaffold(body: Text('e2e'))));

/// Runs [body] with a fresh [AudioPlayer] that is disposed afterwards. The player talks to the native side through
/// JNI (Android) or the Objective-C runtime (iOS, macOS), not a method channel.
Future<void> withPlayer(PatrolIntegrationTester $, Future<void> Function(AudioPlayer player) body) async {
  await pumpHost($);
  final player = AudioPlayer();
  addTearDown(player.dispose);
  await body(player);
}

void expectNear(Duration? actual, Duration expected, {Duration tolerance = const Duration(milliseconds: 200)}) {
  expect(actual, isNotNull, reason: 'expected about $expected');
  expect((actual! - expected).abs(), lessThanOrEqualTo(tolerance), reason: 'expected about $expected, got $actual');
}

Future<void> waitForPosition(AudioPlayer player, Duration position) =>
    player.positionStream.firstWhere((p) => p >= position).timeout(nativeTimeout);

Future<void> waitForIndex(AudioPlayer player, int index) =>
    player.currentIndexStream.firstWhere((i) => i == index).timeout(nativeTimeout);
