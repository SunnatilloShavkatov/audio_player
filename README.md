# audio_player

A feature-rich, high-performance audio player plugin for Flutter. Play, loop, clip, and sequence audio from any source (assets, local files, remote URLs, and byte streams) in gapless playlists.

[![pub package](https://img.shields.io/badge/pub-v1.0.0-blue.svg)](https://github.com/SunnatilloShavkatov/audio_player)
[![license](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
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

- 🎵 **Any Source**: Remote URLs, local device files, app assets, and custom byte streams (`StreamAudioSource`).
- 🔁 **Gapless Playlists**: Smooth, uninterrupted track transitions with dynamic queue management (add, remove, move).
- 🎚️ **Precision Controls**: Full control over volume, speed, pitch, seeking, looping, and shuffling.
- ✂️ **Audio Clipping**: Play millisecond-precise segments of any track without modifying files.
- ⚡ **Caching**: Stream remote audio while caching to disk for offline playback (`LockCachingAudioSource`).
- 📻 **Streaming Protocols**: Native support for HLS (`.m3u8`), DASH (`.mpd`), and ICY radio metadata.
- 🎛️ **Audio Effects**: Built-in 5-band equalizer & loudness enhancer on Android.
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
  audio_player: ^1.0.0
```

---

## Platform Setup

### Android

1. Add `INTERNET` permission to `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```

2. If you stream cleartext HTTP audio or use caching/proxy features, enable cleartext traffic in `<application>`:
   ```xml
   <application
       android:usesCleartextTraffic="true"
       ... >
   ```

### iOS

To allow HTTP streaming or local proxy features, add App Transport Security to `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### macOS

1. Add App Transport Security to `macos/Runner/Info.plist`:
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsArbitraryLoads</key>
       <true/>
   </dict>
   ```

2. Allow outgoing network connections in `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:
   ```xml
   <key>com.apple.security.network.client</key>
   <true/>
   ```

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

### Stream Caching

Play remote audio while simultaneously downloading and caching it for offline playback:

```dart
final source = LockCachingAudioSource(
  Uri.parse('https://example.com/podcast.mp3'),
);

await player.setAudioSource(source);
player.play();
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

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
