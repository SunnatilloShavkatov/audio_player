import 'package:audio_player_example/example_effects.dart' as effects;
import 'package:audio_player_example/example_playlist.dart' as playlist;
import 'package:audio_player_example/example_radio.dart' as radio;
import 'package:audio_player_example/main.dart' as single;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Renders every demo screen at phone and desktop sizes, in light and dark mode, and checks for layout errors.
void main() {
  final screens = <String, Widget Function()>{
    'single': () => const single.MyApp(),
    'playlist': () => const playlist.MyApp(),
    'effects': () => const effects.MyApp(),
    'radio': () => const radio.MyApp(),
  };
  const sizes = {'phone': Size(390, 844), 'desktop': Size(1280, 800)};

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
      for (final brightness in Brightness.values) {
        testWidgets('$name renders on $sizeName in ${brightness.name} mode', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

          await tester.pumpWidget(build());
          await tester.pump();
          expect(tester.takeException(), isNull);

          // The volume chip opens the playback settings sheet.
          await tester.tap(find.byTooltip('Volume'));
          await tester.pumpAndSettle();
          expect(find.text('Playback'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
