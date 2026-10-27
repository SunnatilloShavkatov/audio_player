## 2.2.0

* Fix: a pending `pause()` no longer calls a retired native player when `stop()` or `dispose()` interrupts loading.
* Fix: a native error whose `details` is a string no longer surfaces as a `TypeError` instead of a `PlayerException`.
* Fix: `setPitch` and `setSkipSilenceEnabled` no longer write rollback values to closed streams after disposal.
* Fix: a `seek` before the first `play()` is now where the native player starts, instead of index 0 at zero.
* Fix: a `seek` that is dropped while loading no longer clears the initial index and position.
* Fix: a second `setAudioSources`/`setUrl` while the first is starting no longer fails with "Loading interrupted" and leaves the player unusable.
* Fix: playlist edits made while the native player starts are no longer applied twice on the native side.
* Fix: the `shuffleOrder` passed to the constructor is used by `setAudioSources`.
* Fix: `stop()` followed by `play()` keeps the shuffle order instead of reshuffling it.
* Fix: `AudioPlayer.clearAssetCache` no longer throws when nothing was cached.
* Fix (Android): a failed `load()` (for example an `initialIndex` out of range) no longer breaks later loads or leaks the player.
* Fix (Android): errors complete a pending `seek()`, `seek()` to the end of the last item completes, and `seek()` with an index outside the playlist fails instead of hanging.
* Fix (Android): `setAllowsExternalPlayback` no longer throws `MissingPluginException`.
* Fix (Android): the position estimate is corrected when playback is suppressed or resumed, for example during a short audio focus loss.
* Fix (Android): a bad `AudioLoadConfiguration` no longer leaves channel handlers registered.
* Fix (Android): players disposed while the engine is destroyed or restarted no longer send messages.
* Fix (iOS, macOS): `setAudioSources([])` and `clip()` on an already loaded URI no longer wait forever.
* Fix (iOS, macOS): a seek to another item near that item's position no longer leaves the state `completed`, and paused seeks no longer stay in `buffering`.
* Fix (iOS, macOS): every `seek` is answered, including superseded and failed ones and ones pending at dispose, and late seek callbacks send nothing during engine teardown.
* Fix (iOS, macOS): `seek(null)` goes to the start of the item instead of the end; live streams still go to the live edge.
* Fix (iOS, macOS): moving or inserting without a current item no longer reports a `currentIndex` of -1, and the duration is unknown instead of zero when there is no current source.
* Fix (iOS, macOS): a reused loop item no longer keeps the previous clip's start and end, and ICY metadata is no longer duplicated.

## 2.1.1

* Fix: `setVolume` and `setSpeed` no longer write rollback values to closed streams when disposal finishes
  before a pending platform call fails. The original platform error is still rethrown.

## 2.1.0

* **Breaking:** removed the local HTTP proxy server. Request headers and the user agent are always sent by the native
  players: on Android through ExoPlayer's `setUserAgent` and `setDefaultRequestProperties`, on iOS/macOS through
  `AVURLAssetHTTPUserAgentKey` or `AVURLAssetHTTPHeaderFieldsKey`. The `useProxyForRequestHeaders` constructor
  parameter is removed, and apps no longer need `NSAllowsLocalNetworking` for this plugin.
* **Breaking:** removed `StreamAudioSource`, `StreamAudioResponse` and `LockCachingAudioSource` (including
  `LockCachingAudioSource.downloadProgressStream` and `clearCache`), which were served through the proxy.
* **Breaking:** removed the web-only `AudioPlayer.setWebCrossOrigin`, `setWebSinkId`, `webCrossOrigin` and
  `webSinkId`, and the `WebCrossOrigin` enum. This package has no web implementation, so they never had an effect.
* **Breaking:** removed the `@visibleForTesting` members of `AudioPlayer` from the public API (`testIdlePlatform`,
  `testConvertException`, `testCreatePlaylist`, `testPlaylistLength`, `testPlaylistGet`, `testPluginLoadRequest`,
  `testEncodeDataUrl`, `testProxyStart` and `testProxyStop`). The package's own tests reach them through an extension
  that `package:audio_player/audio_player.dart` does not export.
* **Breaking:** `setClip` throws a `StateError` instead of a plain `Exception` when the playlist does not contain
  exactly one `UriAudioSource`. Code that catches `Exception` around `setClip` must catch `StateError` instead.
* **Breaking:** removed `DarwinAudioEffect` and `AudioPipeline.darwinAudioEffects`. No effect implemented them and
  the iOS/macOS player never applied them.
* **Breaking:** removed the `audio_session` dependency. The package now exports its own `AndroidAudioAttributes`,
  `AndroidAudioContentType`, `AndroidAudioFlags` and `AndroidAudioUsage` with the same members, so
  `setAndroidAudioAttributes` takes these types and code that passed the `audio_session` ones must switch. An app that
  imports both packages needs `hide` or a prefix on one of them. `AudioSession.instance.configure(...)` is no longer
  needed or read: call `setAndroidAudioAttributes` to describe the audio.
* **Breaking:** removed the `androidApplyAudioAttributes` constructor parameter. The attributes passed to
  `setAndroidAudioAttributes` are always applied.
* The platform players now handle audio focus, interruptions and the audio session themselves, and the constructor's
  `handleInterruptions` and `handleAudioSessionActivation` parameters are sent in the `init` message (new keys
  `handleInterruptions` and `handleAudioSessionActivation`). Previously `audio_session` did this from Dart.
  * Android: ExoPlayer requests audio focus (`handleInterruptions`, on by default; the default attributes are
    `USAGE_MEDIA`). A transient loss of focus suppresses playback and resumes it afterwards without changing
    `playing`. A permanent loss of focus or unplugged headphones pauses the player, and `playing` becomes `false`.
  * iOS: the player activates the `AVAudioSession` before playing (`handleAudioSessionActivation`), switching the
    `ambient` and `soloAmbient` categories to `playback`, and `play()` leaves `playing` `false` if activation fails.
    With `handleInterruptions` it pauses on an interruption, resumes when the system says it should, and pauses when
    the output device (such as headphones) is removed. macOS has no audio session, so none of this applies there.
* Fix: `play()` no longer waits forever when the platform player cannot be created or configured. It completes with
  the error (a `PlayerException` for platform errors), `playing` reverts to `false`, the error is reported on
  `errorStream`, and the player stays usable instead of failing every later call with the same error. `load()` and
  the `set...` loading methods throw the error the same way.
* Fix: `play()` also completes once playback is paused or stopped, or completes, when the activation that would have
  sent its play request was superseded (for example by `stop()`).
* Fix: on iOS and macOS, an `AudioPipeline` with Android audio effects made loading fail with a
  `MissingPluginException`. Android effects now keep their settings there without reaching the platform player.
* Fix: on Android, `shuffle()` now updates the native shuffle order, so playback advances in the new order.
* Android: the playlist uses ExoPlayer's own playlist API and `ClippingMediaSource.Builder` instead of the deprecated
  `ConcatenatingMediaSource` and `ClippingMediaSource` constructor, and the file-wide deprecation suppression is gone.
* Removed the unused looping source from the Android, iOS/macOS and platform interface code, and the web-only
  data URL path for assets.
* Added integration tests (`example/integration_test`) that run the native players on Android, iOS and macOS, and CI
  jobs that build the macOS example and run the integration tests on an Android emulator.
* `setVolume` and `setSpeed` revert `volume` and `speed` to their previous values if the platform call fails, like
  `setPitch`.
* Errors on the platform's playback event stream other than the native player errors (which `errorStream` already
  reports from the playback event) are reported through `FlutterError.reportError` instead of being dropped.
* Docs: the `AudioPlayer` constructor documents `userAgent`, `handleAudioSessionActivation`, `audioLoadConfiguration`
  and `androidAudioOffloadPreferences` by their public names, and `setPreferredPeakBitRate` documents its default of
  0 (no limit).
* Removed the `crypto`, `path` and `meta` dependencies.

## 1.0.1

* Fix: on iOS/macOS an invalid source passed to `load` no longer leaves the player stuck in `loading`, and a load
  that is superseded or disposed now completes with an abort error instead of never completing.
* Fix: disposing an iOS/macOS player that never loaded now releases its channels, and engine teardown no longer
  replies to pending calls through the messenger.
* Fix: live streams on iOS/macOS report an unknown (`null`) duration instead of `Duration.zero`, matching Android.
* `setPitch` and `setSkipSilenceEnabled` are accepted as no-ops on iOS/macOS instead of failing; `setPitch` reverts
  `pitch` if the platform call fails.
* `setSpeed` and `setPitch` throw `ArgumentError` for values that are not greater than 0, and `setVolume` for
  negative values.
* Fix: `play()` no longer hangs when the audio session cannot be activated, or when the playlist is empty (it then
  completes once playback is paused or stopped).
* Fix: `positionStream` and `createPositionStream` stop their timers when their last listener cancels.
* Fix: sources removed from the playlist (or replaced by `setAudioSources`) are released.
* Proxy server: unknown paths get `404` and other methods `405` instead of an uncaught error; network errors close
  the request; HTTP clients are closed after each request; HLS playlists are also detected by the response content
  type; concurrent starts share one server.
* Asset cache files are written atomically.
* Android: a failing audio effect no longer leaves the player without its event listener; an `ExoPlaybackException`
  of an unexpected type no longer throws while being logged; sources from earlier playlists are released on `load`.
* Android: removed the unused `media3-exoplayer-smoothstreaming` dependency.
* Removed the leftover cleanup of an old asset cache directory that this package never created.
* Docs: iOS/macOS setup uses `NSAllowsLocalNetworking`; added background playback notes and platform limits for
  pitch, silence skipping and the equalizer.

## 1.0.0

* Initial release.
