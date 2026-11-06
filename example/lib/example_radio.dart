import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const new({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    unawaited(_init());
  }

  Future<void> _init() async {
    // Inform the operating system of our app's audio attributes.
    // We pick a reasonable default for an app that plays speech.
    await _player.setAndroidAudioAttributes(
      const AndroidAudioAttributes(contentType: AndroidAudioContentType.speech, usage: AndroidAudioUsage.media),
    );
    // Listen to errors during playback.
    _player.errorStream.listen((e) {
      debugPrint('A stream error occurred: $e');
    });
    // Try to load audio from a source and catch any errors.
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse('https://stream-uk1.radioparadise.com/aac-320')));
    } on PlayerException catch (e) {
      debugPrint('Error loading audio source: $e');
    }
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    // Release decoders and buffers back to the operating system making them
    // available for other apps to use.
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Release the player's resources when not in use. We use "stop" so that
      // if the app resumes later, it will still remember what position to
      // resume from.
      unawaited(_player.stop());
    }
  }

  @override
  Widget build(BuildContext context) => DemoApp(
    title: 'Live radio',
    home: Scaffold(
      appBar: AppBar(title: const Text('Live radio')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  // ICY metadata carries the current song title and, for some stations, cover art.
                  StreamBuilder<IcyMetadata?>(
                    stream: _player.icyMetadataStream,
                    builder: (context, snapshot) {
                      final metadata = snapshot.data;
                      final title = metadata?.info?.title;
                      return NowPlaying(
                        title: title == null || title.isEmpty ? 'Waiting for song info…' : title,
                        subtitle: metadata?.headers?.name ?? metadata?.headers?.genre,
                        artworkUrl: metadata?.info?.url,
                        placeholderIcon: Icons.radio_rounded,
                        badge: const _LiveBadge(),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  PlayPauseButton(_player),
                  const SizedBox(height: 24),
                  PlaybackSettingsBar(_player, showSpeed: false, showPitch: false),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Small "LIVE" chip shown above the station's current song.
class _LiveBadge extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(Icons.circle, size: 8, color: colors.error),
            Text(
              'LIVE',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.onErrorContainer, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}
