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
