// Regenerates lib/src/bindings/audio_player_api.g.dart from the compiled Kotlin facade. Run from the package root:
//   (cd example/android && ./gradlew :audio_player:compileDebugKotlin)
//   dart run tool/jnigen.dart
// The first step compiles the Android plugin classes only; the app is not built or run.
import 'dart:io';

import 'package:jnigen/jnigen.dart';

Future<void> main() async {
  final Uri packageRoot = Platform.script.resolve('../');
  final Uri classes = packageRoot.resolve('example/build/audio_player/tmp/kotlin-classes/debug/');
  if (!Directory.fromUri(classes).existsSync()) {
    stderr.writeln('Compiled classes not found at ${classes.toFilePath()}; run the Gradle step above first.');
    exit(1);
  }
  await JniGenerator(
    input: Input(
      classPath: <Uri>[classes],
      classes: <String>['uz.plugin.audio_player.AudioPlayerApi'],
      backend: SummarizerBackend.asm,
    ),
    output: Output(
      dart: DartOutput(
        path: packageRoot.resolve('lib/src/bindings/audio_player_api.g.dart'),
        structure: OutputStructure.singleFile,
      ),
    ),
  ).generate();
}
