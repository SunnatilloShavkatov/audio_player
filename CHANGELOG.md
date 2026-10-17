## 2.0.0

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
* `setVolume` and `setSpeed` revert `volume` and `speed` to their previous values if the platform call fails, like
  `setPitch`.
* Errors on the platform's playback event stream other than the native player errors (which `errorStream` already
  reports from the playback event) are reported through `FlutterError.reportError` instead of being dropped.
* Docs: the `AudioPlayer` constructor documents `userAgent`, `handleAudioSessionActivation`, `audioLoadConfiguration`
  and `androidAudioOffloadPreferences` by their public names, and `setPreferredPeakBitRate` documents its default of
  0 (no limit).
* Removed the `crypto` dependency.

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
