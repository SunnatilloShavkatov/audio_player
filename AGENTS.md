# AGENTS.md

`audio_player`: Flutter audio plugin (gapless playlists, clipping, HLS/DASH, effects),
published as `uz.plugin.audio_player`.

## Layout

- `lib/src/audio_player.dart` — `AudioPlayer` + streams (RxDart); `lib/src/sources/` — `AudioSource` types;
  `lib/src/platform_interface/` — platform interface, `AndroidAudioPlayerPlatform` / `DarwinAudioPlayerPlatform` over a shared JSON transport (`native_audio_player_platform.dart`); `lib/src/bindings/` — generated JNI / Objective-C bindings (`*.g.dart`); `lib/src/internal/` — idle player,
  helpers (not public API). `lib/audio_player.dart` is the public barrel. There is no local proxy: request headers
  and the user agent go to the native players in the source messages.
- Android (Media3/ExoPlayer): `android/src/main/kotlin/uz/plugin/audio_player/`. `AudioPlayer.kt` holds the state;
  method calls, commands, ExoPlayer callbacks, playback events, sources and effects live in their own files.
  `AudioPlayerHost.kt` routes the JNI calls to players. Android native code is Kotlin only: no `.java`
  files, including the jnigen facade `AudioPlayerApi.kt` (Strings and callbacks only); jnigen reads the compiled
  classes (ASM backend). Keep it through R8 in `android/consumer-rules.pro`.
- Keep every Swift and Kotlin file under 300 lines: split by concern (Kotlin: helper classes and `AudioPlayer.*`
  extension functions; Swift: `AudioPlayer+<Concern>.swift` extensions) instead of growing one file.
- iOS + macOS (AVPlayer): one shared Swift set in `darwin/audio_player/Sources/audio_player/`
  (`#if os(iOS)` / `#elseif os(macOS)`). A Swift change hits both platforms.
- Tests: `test/` (mocktail); native players at runtime: Patrol tests in `example/patrol_test/` (`test_bundle.dart` is generated, not committed). Demo app: `example/`.
- No method or event channels: Dart calls `AudioPlayerApi` (Android: JNI to the Java facade; iOS/macOS: Objective-C
  runtime to the Swift `@objc(AudioPlayerApi)` class). Requests and replies are JSON of the platform interface
  messages, events come back through listener callbacks. Dart, Swift and Kotlin must agree on method names and
  message shape. After changing the facade run `dart run tool/jnigen.dart`; after changing `AudioPlayerApi.swift`
  update `darwin/audio_player/Sources/audio_player_c/audio_player_api.h` to match exactly (a mismatch crashes at
  runtime) and run `dart run tool/ffigen.dart`. Generated bindings are committed.

## Commands

```bash
flutter pub get && flutter analyze && flutter test
dart format --set-exit-if-changed .                          # width 120
```

Agents may compile Android (Gradle / `flutter build apk --debug`). The user runs the iOS/macOS builds and all
integration tests themselves; agents must NOT run those (see Rules):

```bash
cd example && flutter build apk --debug                      # compiles Kotlin (agents may run this)
cd example && flutter build ios --simulator --no-codesign    # compiles Swift
cd example && flutter build macos --debug                    # compiles Swift for macOS
cd example && patrol test -d <device id>                     # Patrol e2e on the native players (emulator, simulator)
cd example && patrol test -d <device id> -t patrol_test/<file>.dart   # one file
```

## Rules

- Dart `>=3.13.0`, Flutter `>=3.47.0`. Lints: `package:analysis_lints`; fix warnings in code you touch.
- Document public API with `///`. Public API, channel message or observable native behavior change → add
  `CHANGELOG.md` entry; update `README.md` if usage changes.
- Don't edit `build/`, `.dart_tool/`, `example/build/`, `*.g.dart`. Match surrounding style; no new dependencies
  without reason.
- Never `git commit` or push; leave changes in the working tree.
- Never create branches or worktrees; work in the current checkout and leave changes staged for review.
- Android: agents may compile (`gradlew`, `flutter build apk`) when needed, e.g. for jnigen's compiled-class input.
  Never run the app or its integration tests on an emulator.
- Never build or run the example app or its integration tests for iOS or macOS (`flutter build ios|macos`,
  `flutter run`, `flutter test integration_test`, `xcodebuild`, simulator launches). The user does that.
  `.claude/settings.json` denies these commands. Edit the Swift carefully by reading it, and say it was not
  compiled or run.
- Before saying a change works: run `flutter analyze`, `dart format --set-exit-if-changed .` and `flutter test`. When
  native code changed, state which platforms were not compiled or run (Android Kotlin only if not compiled), and
  name which platforms the user should build and test.
- Unit tests run on the development machine: platform-specific code checks `_isAndroid()`, which tests override with
  `AudioPlayerTestHooks.testTargetPlatform`. Don't add test-only branches to `lib/`.

## MCP servers and tools

- Use only: `dart` (analyze, pub, pub.dev search) and GitHub (`gh` CLI or the GitHub MCP; the repo is
  `SunnatilloShavkatov/audio_player`).
- Don't use in this repo: `glab` (GitLab), Outlook/Teams/SharePoint, Atlassian (Jira/Confluence), Figma, Firebase,
  `youtrack`. They are configured for other projects; don't load their tools or suggest them here.

## Native lifecycle

- `AudioPlayerPlugin.deinit` runs while the `FlutterEngine` is being destroyed. Code reached from it
  (`AudioPlayerApi.detach`, `AudioPlayer.dispose(calledFromDeinit: true)`, `PlayerEventSink.dispose`) must NOT call the Dart
  listener blocks or reply to pending calls: the Dart side is going away. Check `calledFromDeinit` before any send.
- Explicit Dart disposal (`disposePlayer`, `disposeAllPlayers`) may send the final events and replies.
- Android mirrors this in `AudioPlayer.kt` / `AudioPlayerHost.kt` (`detach`, `restart`); keep both in sync.
