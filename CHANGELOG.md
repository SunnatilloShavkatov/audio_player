## 1.2.0

### Fixed

* A player created in a background isolate no longer takes over the playback events of the root isolate's players
  (Android, iOS, macOS): each isolate registers its own listener, and a player's events go only to the isolate that
  created it. `disposeAllPlayers` frees only the calling isolate's players.
* iOS/macOS: key-value changes, seek completions, replies and events that AVFoundation reports on another thread are
  handled on the main thread, where the player state lives.
* Android: a call that fails synchronously in JNI completes its future with a `PlatformException` instead of throwing.
* Event listening is retried on the next call when registering the native listener fails.
* macOS: the players of a destroyed Flutter engine are released (macOS never calls `detachFromEngine`).

### Changed

* Require Flutter 3.47 and Dart 3.13 (was Flutter 3.50 and Dart 3.14); CI runs on Flutter 3.47.0.
* Android: replies to Dart go through one JNI callback per isolate with a call id, instead of a new proxy and receive
  port per call that only closed once Java collected it.
* Windows, Linux and other unsupported platforms get `UnsupportedAudioPlayerPlatform`, which fails every call with an
  `UnsupportedError`, instead of the iOS/macOS platform failing in the Objective-C runtime.
* Hot restart releases the native players of the restarted engine on iOS and macOS too.
* iOS/macOS: Swift Package Manager only; the CocoaPods podspec was removed.
* The JNI facade (`AudioPlayerApi.kt`) and the Objective-C API (`audio_player_api.h`) take a listener id and call ids;
  the generated bindings were regenerated.

## 1.1.3

### Fixed

* Apps that run more than one Flutter engine: each engine now has its own players and playback events on Android, iOS
  and macOS, and closing one engine no longer stops playback in another.

## 1.1.2

* Android: the audio renderer falls back to the next decoder when the preferred one fails to initialize or decode, instead of failing playback with a generic source error on some devices.

## 1.1.1

* Android: JNI callback and listener proxies are released on the Dart side once handed to Kotlin, instead of pinning a global reference until the next Dart GC.
* Android: media3 `UnstableApi` is opted in per file (`androidx.annotation.OptIn`), so `lint` passes with `UnsafeOptInUsageError` enabled.
* Android: the plugin's `kotlin { compilerOptions }` block moved to the top level; it builds with AGP built-in Kotlin on and off.
* `tool/jnigen.dart` reads the freshest compiled facade instead of a hardcoded class directory.
* Example: Gradle daemon on JDK 21, foojay resolver 1.0.0, no `android.enableJetifier`.

## 1.1.0

* Replace method and event channels with direct native calls: JNI (`jni`, `jnigen`) on Android and the Objective-C
  runtime (`objective_c`, `ffigen`) on iOS and macOS. The public Dart API is unchanged.
* Android: the JNI facade `AudioPlayerApi` is Kotlin (bindings generated from the compiled classes), plugin `compileSdk` 37, R8 keep rules for the facade (`consumer-rules.pro`).
* Example: the integration tests are now Patrol e2e tests in `example/patrol_test/` (`patrol test -d <device>`).
* Android: a request with a missing or wrongly typed field now fails with the `invalid_argument` code (it was `error`).
* Dispose no longer sends an unhandled native `dispose` call. A platform without `disposePlayer` is still disposed through its instance.
* `AudioPlayerPlatform` now defaults to `AndroidAudioPlayerPlatform` / `DarwinAudioPlayerPlatform`;
  `MethodChannelAudioPlayerPlatform` is removed.

## 1.0.1

* Require Dart 3.14 and Flutter 3.50.
* Align example Gradle setup: Gradle 9.5.0, Android Gradle Plugin 9.3.1, Kotlin 2.4.20.
* Update dependencies: `synchronized` ^3.6.1+1, `analysis_lints` ^1.1.1.

## 1.0.0

* Initial release on pub.dev.
* Gapless playlists, clipping, looping, shuffle, and seeking across asset, file and URL sources.
* HLS and DASH streaming, request headers and user agent passed to the native players.
* Audio effects, speed, pitch, volume and skip-silence controls.
* Android (Media3/ExoPlayer), iOS and macOS (AVPlayer) support.
