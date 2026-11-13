// Regenerates lib/src/bindings/audio_player_darwin.g.dart and the Objective-C wrapper
// darwin/audio_player/Sources/audio_player_c/audio_player_darwin.m from audio_player_api.h.
// Run from the package root: `dart run tool/ffigen.dart`.
import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final Uri packageRoot = Platform.script.resolve('../');
  final Uri cSources = packageRoot.resolve('darwin/audio_player/Sources/audio_player_c/');
  await FfiGenerator(
    output: Output(
      dart: DartOutput(path: packageRoot.resolve('lib/src/bindings/audio_player_darwin.g.dart')),
      objectiveCFile: cSources.resolve('audio_player_darwin.m'),
    ),
    objectiveC: const ObjectiveC(),
    input: Input(entryPoints: <Uri>[cSources.resolve('audio_player_api.h')]),
    visitors: <Visitor>[
      Visitor(
        objCInterface: (node) {
          if (node.originalName == 'AudioPlayerApi') {
            node.isIncluded = true;
          }
        },
      ),
    ],
  ).generate();
}
