# audio_player

A feature-rich, high-performance audio player plugin for Flutter. Play, loop, clip, and sequence audio from assets, local files and remote URLs in gapless playlists.

[![pub package](https://img.shields.io/badge/pub-v2.1.1-blue.svg)](https://pub.dev/packages/audio_player)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-android%20%7C%20ios%20%7C%20macos-lightgrey.svg)](https://github.com/SunnatilloShavkatov/audio_player)

---

## Platform Support

| Platform    | Supported | Engine                                       |
|-------------|:---------:|----------------------------------------------|
| **Android** |    ✅     | AndroidX Media3 (ExoPlayer 1.11.1) — API 24+ |
| **iOS**     |    ✅     | AVFoundation / AVPlayer — iOS 15.0+          |
| **macOS**   |    ✅     | AVFoundation / AVPlayer — macOS 11.0+        |
| **Web**     |    ❌     | *Currently not supported*                    |
| **Windows** |    ❌     | *Currently not supported*                    |
| **Linux**   |    ❌     | *Currently not supported*                    |

---

## Features

- 🎵 **Any Source**: Remote URLs (with custom request headers and user agent), local device files and app assets.
- 🔁 **Gapless Playlists**: Smooth, uninterrupted track transitions with dynamic queue management (add, remove, move).
- 🎚️ **Precision Controls**: Full control over volume, speed, seeking, looping, and shuffling. Pitch and silence skipping are Android only (accepted as no-ops on iOS/macOS).
- ✂️ **Audio Clipping**: Play millisecond-precise segments of any track without modifying files.
- 📻 **Streaming Protocols**: Native support for HLS (`.m3u8`), DASH (`.mpd`), and ICY radio metadata.
- 🎛️ **Audio Effects**: Equalizer (band count depends on the device) & loudness enhancer on Android.
- 📡 **Reactive Architecture**: RxDart streams for playback state, position, buffer, and duration.

---

## Installation

Add `audio_player` to your Flutter project:

```bash
flutter pub add audio_player
```

Or add it to `pubspec.yaml`:

```yaml
dependencies:
  audio_player: ^2.1.1
```

---

## Platform Setup

### Android

1. Add `INTERNET` permission to `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```

2. If you stream from `http://` (not `https://`) URLs, enable cleartext traffic in `<application>`:
   ```xml
   <application
       android:usesCleartextTraffic="true"
       ... >
   ```

### iOS

No setup is needed for `https://` URLs. Only if you stream from `http://` URLs, add an `NSAppTransportSecurity`
entry to `ios/Runner/Info.plist`: an `NSExceptionDomains` entry for those hosts or, less strictly,
`NSAllowsArbitraryLoads`.

### macOS

1. Only if you stream from `http://` URLs, add App Transport Security to `macos/Runner/Info.plist` as described
   for iOS above.

2. Allow outgoing network connections in `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
   ```xml
   <key>com.apple.security.network.client</key>
   <true/>
   ```

### Background playback

This plugin plays audio but does not keep your app alive in the background or show media controls.

- **iOS:** add `audio` to `UIBackgroundModes` in `ios/Runner/Info.plist`.
- **Android:** run playback from a foreground service with a media session (for example via a package such as
  `audio_service`); otherwise the system may stop playback once the app is in the background.

---

## Quick Start

```dart
import 'package:audio_player/audio_player.dart';

final player = AudioPlayer();

// 1. Load audio from a URL, asset, or file
await player.setUrl('https://example.com/audio.mp3');

// 2. Playback controls
player.play();                         // Start playing
await player.pause();                  // Pause
await player.seek(const Duration(seconds: 30)); // Seek to 30s
await player.setSpeed(1.5);            // 1.5x speed
await player.setVolume(0.8);           // 80% volume

// 3. Clean up
await player.dispose();
```

---

## Common Use Cases

### Gapless Playlist

```dart
// Load playlist
await player.setAudioSources([
  AudioSource.uri(Uri.parse('https://example.com/song1.mp3')),
  AudioSource.uri(Uri.parse('https://example.com/song2.mp3')),
  AudioSource.asset('assets/audio/song3.mp3'),
]);

// Navigation
await player.seekToNext();
await player.seekToPrevious();

// Modes
await player.setLoopMode(LoopMode.all);       // Loop playlist
await player.setShuffleModeEnabled(true);    // Shuffle
```

### Reactive State & Streams

```dart
// Listen to combined playback state
player.playerStateStream.listen((state) {
  print('Playing: ${state.playing}, State: ${state.processingState}');
});

// Position & duration
player.positionStream.listen((pos) => print('Position: $pos'));
player.durationStream.listen((dur) => print('Duration: $dur'));
```

### Request Headers

Headers and the user agent are sent by the platform player itself (ExoPlayer on Android, `AVURLAsset` options on
iOS/macOS):

```dart
final player = AudioPlayer(userAgent: 'MyApp/1.0');
await player.setUrl(
  'https://example.com/stream.m3u8',
  headers: {'Authorization': 'Bearer <token>'},
);
```

### Audio Clipping

Play only a specific portion of a track:

```dart
await player.setUrl('https://example.com/audio.mp3');
await player.setClip(
  start: const Duration(seconds: 10),
  end: const Duration(seconds: 40),
);
player.play();
```

---

## Example App

Check out the full sample project in the [`example`](example) directory:

```bash
cd example
flutter run
```

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

The Android implementation uses AndroidX Media3 (ExoPlayer), licensed under the Apache License 2.0.
