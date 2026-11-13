// Regenerates lib/src/bindings/audio_player_api.g.dart from the compiled Kotlin facade. Run from the package root:
//   (cd example/android && ./gradlew :audio_player:compileDebugKotlin)
//   dart run tool/jnigen.dart
// The first step compiles the Android plugin classes only; the app is not built or run.
import 'dart:io';

import 'package:jnigen/jnigen.dart';

Future<void> main() async {
  final Uri packageRoot = Platform.script.resolve('../');
  final Uri? classes = _newestClasses(packageRoot.resolve('example/build/audio_player/'));
  if (classes == null) {
    stderr.writeln('No compiled AudioPlayerApi under example/build; run the Gradle step above first.');
    exit(1);
  }
  stdout.writeln('Reading classes from $classes');
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

// AGP's built-in Kotlin (android.builtInKotlin=true) and the kotlin-android plugin write classes to different
// directories, and a switch between them leaves the other one stale. The freshest facade class wins.
Uri? _newestClasses(Uri pluginBuild) {
  const String facade = 'uz/plugin/audio_player/AudioPlayerApi.class';
  Uri? newest;
  DateTime? newestModified;
  for (final String dir in <String>[
    'intermediates/built_in_kotlinc/debug/compileDebugKotlin/classes/',
    'tmp/kotlin-classes/debug/',
  ]) {
    final Uri classes = pluginBuild.resolve(dir);
    final File file = File.fromUri(classes.resolve(facade));
    if (!file.existsSync()) {
      continue;
    }
    final DateTime modified = file.lastModifiedSync();
    if (newestModified == null || modified.isAfter(newestModified)) {
      newest = classes;
      newestModified = modified;
    }
  }
  return newest;
}
