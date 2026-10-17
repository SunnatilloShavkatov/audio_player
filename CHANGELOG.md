## Unreleased

* **Breaking:** removed the local HTTP proxy server. Request headers and the user agent are always sent by the native
  players: on Android through ExoPlayer's `setUserAgent` and `setDefaultRequestProperties`, on iOS/macOS through
  `AVURLAssetHTTPUserAgentKey` or `AVURLAssetHTTPHeaderFieldsKey`. The `useProxyForRequestHeaders` constructor
  parameter is removed, and apps no longer need `NSAllowsLocalNetworking` for this plugin.
* **Breaking:** removed `StreamAudioSource`, `StreamAudioResponse` and `LockCachingAudioSource`, which were served
  through the proxy.
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
