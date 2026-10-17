# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

`audio_player` is a Flutter plugin for audio playback (gapless playlists, clipping, caching, HLS/DASH, effects).
It is a port in the style of `just_audio`, published as `uz.plugin.audio_player`.

| Platform | Engine                      | Source                                                        |
|----------|-----------------------------|---------------------------------------------------------------|
| Android  | AndroidX Media3 (ExoPlayer) | `android/src/main/kotlin/uz/plugin/audio_player/`             |
| iOS      | AVFoundation / AVPlayer     | `darwin/audio_player/Sources/audio_player/`                   |
| macOS    | AVFoundation / AVPlayer     | `darwin/audio_player/Sources/audio_player/` (shared with iOS) |

iOS and macOS share one Swift source set (`sharedDarwinSource: true`). Platform differences are handled with
`#if os(iOS)` / `#elseif os(macOS)`. A Swift change affects both; do not fix one and forget the other.

## Layout

- `lib/audio_player.dart` — public barrel export.
- `lib/src/audio_player.dart` — the `AudioPlayer` class and its streams (RxDart).
- `lib/src/sources/` — `AudioSource` types (URI, concatenating, clipping, looping, stream).
- `lib/src/platform_interface/` — platform interface and the `MethodChannel` implementation.
- `lib/src/internal/` — local proxy HTTP server, idle player, utils. Not public API.
- `darwin/`, `android/` — native implementations.
- `test/` — Dart unit tests (mockito). `example/` — demo app plus `example/integration_test/`.

Channel names: methods `uz.plugin.audio_player.methods`; per-player events
`uz.plugin.audio_player.events.<playerId>`. Dart and both native sides must agree on them and on the message shape.

## Commands

```bash
flutter pub get
flutter analyze
dart format --set-exit-if-changed .        # page width 120, see analysis_options.yaml
flutter test                               # unit tests in test/
cd example && flutter build ios --simulator --no-codesign   # compiles the Swift sources
cd example && flutter build apk --debug                      # compiles the Kotlin sources
cd example && flutter test integration_test                  # needs a device or simulator
```

Lints come from `package:analysis_lints`. Fix analyzer warnings in code you touch.

## Conventions

- Dart SDK `>=3.13.0`, Flutter `>=3.47.0`. Keep the public API documented with `///` comments.
- Changing a public Dart API, a channel message, or native behavior users can observe: add an entry to
  `CHANGELOG.md` and update `README.md` if the usage changes.
- Do not edit generated or build output (`build/`, `.dart_tool/`, `example/build/`, `*.g.dart`).
- Match the surrounding code's style and comment density. Do not add dependencies without a reason.

## Native lifecycle (important)

- `AudioPlayerPlugin.deinit` runs while the `FlutterEngine` is being destroyed. Anything reached from it
  (`AudioPlayer.dispose(calledFromDeinit: true)`, `BetterEventChannel.dispose`) must **not** send messages through the
  messenger or touch channel handlers. Doing so throws `NSInternalInconsistencyException` ("Sending a message before the
  FlutterEngine has been run") and aborts the app. Check `calledFromDeinit` before any send.
- Explicit disposal from Dart (`disposePlayer`, `disposeAllPlayers`) may send the end-of-stream event and clear handlers.
- Android has a mirror of this lifecycle in `AudioPlayer.kt` / `BetterEventChannel.kt`; keep both in sync when changing
  event-channel behavior.

## Verification

Before saying a change works, run `flutter analyze` and `flutter test`. For native changes, build the example for the
affected platform(s). If you could not run something (no device, simulator, or emulator), say so rather than implying
it was verified.

## Git

Do not run `git commit`, and do not push. Leave changes in the working tree for the maintainer to review and commit.
