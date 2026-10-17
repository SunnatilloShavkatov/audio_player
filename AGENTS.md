# AGENTS.md

`audio_player`: Flutter audio plugin (just_audio-style; gapless playlists, clipping, caching, HLS/DASH, effects),
published as `uz.plugin.audio_player`.

## Layout

- `lib/src/audio_player.dart` — `AudioPlayer` + streams (RxDart); `lib/src/sources/` — `AudioSource` types;
  `lib/src/platform_interface/` — platform interface + `MethodChannel` impl; `lib/src/internal/` — proxy server,
  idle player (not public API). `lib/audio_player.dart` is the public barrel.
- Android (Media3/ExoPlayer): `android/src/main/kotlin/uz/plugin/audio_player/`.
- iOS + macOS (AVPlayer): one shared Swift set in `darwin/audio_player/Sources/audio_player/`
  (`#if os(iOS)` / `#elseif os(macOS)`). A Swift change hits both platforms.
- Tests: `test/` (mocktail). Demo app: `example/`.
- Channels: methods `uz.plugin.audio_player.methods`, events `uz.plugin.audio_player.events.<playerId>`.
  Dart, Swift and Kotlin must agree on names and message shape.

## Commands

```bash
flutter pub get && flutter analyze && flutter test
dart format --set-exit-if-changed .                          # width 120
cd example && flutter build ios --simulator --no-codesign    # compiles Swift
cd example && flutter build apk --debug                      # compiles Kotlin
```

## Rules

- Dart `>=3.13.0`, Flutter `>=3.47.0`. Lints: `package:analysis_lints`; fix warnings in code you touch.
- Document public API with `///`. Public API, channel message or observable native behavior change → add
  `CHANGELOG.md` entry; update `README.md` if usage changes.
- Don't edit `build/`, `.dart_tool/`, `example/build/`, `*.g.dart`. Match surrounding style; no new dependencies
  without reason.
- Never `git commit` or push; leave changes in the working tree.
- Before saying a change works: run analyze + test, and build the example for touched native platforms. If something
  couldn't be run (no device/simulator), say so.

## Native lifecycle

- `AudioPlayerPlugin.deinit` runs while the `FlutterEngine` is being destroyed. Code reached from it
  (`AudioPlayer.dispose(calledFromDeinit: true)`, `BetterEventChannel.dispose`) must NOT send messages or touch channel
  handlers — it throws `NSInternalInconsistencyException` and aborts the app. Check `calledFromDeinit` before any send.
- Explicit Dart disposal (`disposePlayer`, `disposeAllPlayers`) may send end-of-stream and clear handlers.
- Android mirrors this in `AudioPlayer.kt` / `BetterEventChannel.kt`; keep both in sync.
