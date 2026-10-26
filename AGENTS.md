# AGENTS.md

`audio_player`: Flutter audio plugin (gapless playlists, clipping, HLS/DASH, effects),
published as `uz.plugin.audio_player`.

## Layout

- `lib/src/audio_player.dart` — `AudioPlayer` + streams (RxDart); `lib/src/sources/` — `AudioSource` types;
  `lib/src/platform_interface/` — platform interface + `MethodChannel` impl; `lib/src/internal/` — idle player,
  helpers (not public API). `lib/audio_player.dart` is the public barrel. There is no local proxy: request headers
  and the user agent go to the native players in the source messages.
- Android (Media3/ExoPlayer): `android/src/main/kotlin/uz/plugin/audio_player/`.
- iOS + macOS (AVPlayer): one shared Swift set in `darwin/audio_player/Sources/audio_player/`
  (`#if os(iOS)` / `#elseif os(macOS)`). A Swift change hits both platforms.
- Tests: `test/` (mocktail); native players at runtime: `example/integration_test/`. Demo app: `example/`.
- Channels: methods `uz.plugin.audio_player.methods`, events `uz.plugin.audio_player.events.<playerId>`.
  Dart, Swift and Kotlin must agree on names and message shape.

## Commands

```bash
flutter pub get && flutter analyze && flutter test
dart format --set-exit-if-changed .                          # width 120
```

The user runs the native builds and integration tests themselves. Agents must NOT run them (see Rules):

```bash
cd example && flutter build ios --simulator --no-codesign    # compiles Swift
cd example && flutter build macos --debug                    # compiles Swift for macOS
cd example && flutter build apk --debug                      # compiles Kotlin
cd example && flutter test integration_test -d <device>      # runs the native players (emulator, simulator, macos)
```

## Rules

- Dart `>=3.13.0`, Flutter `>=3.47.0`. Lints: `package:analysis_lints`; fix warnings in code you touch.
- Document public API with `///`. Public API, channel message or observable native behavior change → add
  `CHANGELOG.md` entry; update `README.md` if usage changes.
- Don't edit `build/`, `.dart_tool/`, `example/build/`, `*.g.dart`. Match surrounding style; no new dependencies
  without reason.
- Never `git commit` or push; leave changes in the working tree.
- Never create branches or worktrees; work in the current checkout and leave changes staged for review.
- Never build or run the example app or its integration tests for iOS, Android or macOS (`flutter build ios|macos|apk`,
  `flutter run`, `flutter test integration_test`, `xcodebuild`, `gradlew`, simulator or emulator launches). The user
  does that. `.claude/settings.json` denies these commands. Edit the Swift/Kotlin carefully by reading it, and say it
  was not compiled or run.
- Before saying a change works: run `flutter analyze`, `dart format --set-exit-if-changed .` and `flutter test`. When
  native code (Swift, Kotlin) changed, state that it was not compiled or run on any platform, and name which platforms
  the user should build and test.
- Unit tests run on the development machine: platform-specific code checks `_isAndroid()`, which tests override with
  `AudioPlayerTestHooks.testTargetPlatform`. Don't add test-only branches to `lib/`.

## Native lifecycle

- `AudioPlayerPlugin.deinit` runs while the `FlutterEngine` is being destroyed. Code reached from it
  (`AudioPlayer.dispose(calledFromDeinit: true)`, `BetterEventChannel.dispose`) must NOT send messages or touch channel
  handlers — it throws `NSInternalInconsistencyException` and aborts the app. Check `calledFromDeinit` before any send.
- Explicit Dart disposal (`disposePlayer`, `disposeAllPlayers`) may send end-of-stream and clear handlers.
- Android mirrors this in `AudioPlayer.kt` / `BetterEventChannel.kt`; keep both in sync.
