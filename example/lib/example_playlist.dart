import 'dart:async';

import 'package:audio_player/audio_player.dart';
import 'package:audio_player_example/common.dart';
import 'package:audio_player_example/ui/playlist_view.dart';
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
  late AudioPlayer _player;
  static final _playlist = [
    ClippingAudioSource(
      start: const Duration(seconds: 60),
      end: const Duration(seconds: 90),
      child: AudioSource.uri(Uri.parse('https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3')),
      tag: AudioMetadata(
        album: 'Science Friday',
        title: 'A Salute To Head-Scratching Science (30 seconds)',
        artwork: 'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
      ),
    ),
    AudioSource.uri(
      Uri.parse('https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3'),
      tag: AudioMetadata(
        album: 'Science Friday',
        title: 'A Salute To Head-Scratching Science',
        artwork: 'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
      ),
    ),
    AudioSource.uri(
      Uri.parse('https://s3.amazonaws.com/scifri-segments/scifri201711241.mp3'),
      tag: AudioMetadata(
        album: 'Science Friday',
        title: 'From Cat Rheology To Operatic Incompetence',
        artwork: 'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
      ),
    ),
    AudioSource.uri(
      Uri.parse('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'),
      tag: AudioMetadata(
        album: 'SoundHelix',
        title: 'SoundHelix Song 1',
        artwork: 'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
      ),
    ),
  ];
  int _addedCount = 0;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    _player = AudioPlayer(maxSkipsOnError: 3);
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
    try {
      await _player.setAudioSources(_playlist);
    } on PlayerException catch (e) {
      // Catch load errors: 404, invalid url...
      debugPrint('Error loading playlist: $e');
    }
    // Show a snackbar whenever reaching the end of an item in the playlist.
    _player.positionDiscontinuityStream.listen((discontinuity) {
      if (discontinuity.reason == PositionDiscontinuityReason.autoAdvance) {
        _showItemFinished(discontinuity.previousEvent.currentIndex);
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _showItemFinished(_player.currentIndex);
      }
    });
  }

  void _showItemFinished(int? index) {
    if (index == null) {
      return;
    }
    final sequence = _player.sequence;
    if (index >= sequence.length) {
      return;
    }
    final source = sequence[index];
    final metadata = source.tag as AudioMetadata;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text('Finished playing ${metadata.title}'), duration: const Duration(seconds: 1)),
    );
  }

  void _addTrack() {
    unawaited(
      _player.addAudioSource(
        AudioSource.uri(
          Uri.parse('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'),
          tag: AudioMetadata(
            album: 'SoundHelix',
            title: 'SoundHelix Song ${++_addedCount}',
            artwork: 'https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg',
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
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
    title: 'Audio Player',
    scaffoldMessengerKey: _scaffoldMessengerKey,
    home: Scaffold(
      appBar: AppBar(title: const Text('Audio Player')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final playlistHeader = _PlaylistHeader(player: _player, onAdd: _addTrack);
            PlaylistItemInfo describe(IndexedAudioSource source) {
              final metadata = source.tag as AudioMetadata;
              return (title: metadata.title, subtitle: metadata.album, artworkUrl: metadata.artwork);
            }

            // Wide screens: player on the left, playlist on the right.
            if (constraints.maxWidth >= 840) {
              return Row(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: _PlayerPane(_player)),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: PlaylistView(
                      _player,
                      describe: describe,
                      header: playlistHeader,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    ),
                  ),
                ],
              );
            }
            // Narrow screens: the player scrolls away above the playlist.
            return PlaylistView(
              _player,
              describe: describe,
              header: Column(
                children: [
                  Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 16), child: _PlayerPane(_player)),
                  playlistHeader,
                ],
              ),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            );
          },
        ),
      ),
    ),
  );
}

/// Artwork, title, seek bar, transport controls and playback settings of the current item.
class _PlayerPane extends StatelessWidget {
  const new(this.player);

  final AudioPlayer player;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 480),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) {
            final metadata = snapshot.data?.currentSource?.tag as AudioMetadata?;
            return NowPlaying(
              title: metadata?.title ?? 'Nothing playing',
              subtitle: metadata?.album ?? 'Add a track to the playlist',
              artworkUrl: metadata?.artwork,
              maxArtworkSize: 280,
            );
          },
        ),
        const SizedBox(height: 16),
        PlayerSeekBar(player),
        const SizedBox(height: 8),
        TransportControls(
          player,
          leading: [ShuffleButton(player), SkipPreviousButton(player)],
          trailing: [SkipNextButton(player), LoopButton(player)],
          onReplay: () {
            unawaited(player.seek(Duration.zero, index: player.effectiveIndices.first));
          },
        ),
        const SizedBox(height: 16),
        PlaybackSettingsBar(player),
      ],
    ),
  );
}

/// "Playlist" heading with the track count and a button that appends a track.
class _PlaylistHeader extends StatelessWidget {
  const new({required this.player, required this.onAdd});

  final AudioPlayer player;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Playlist', style: theme.textTheme.titleLarge),
                StreamBuilder<List<IndexedAudioSource>>(
                  stream: player.sequenceStream,
                  builder: (context, snapshot) {
                    final count = snapshot.data?.length ?? 0;
                    return Text(
                      '$count ${count == 1 ? 'track' : 'tracks'} · drag to reorder, swipe to remove',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    );
                  },
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(onPressed: onAdd, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
        ],
      ),
    );
  }
}

class AudioMetadata {
  new({required this.album, required this.title, required this.artwork});

  final String album;
  final String title;
  final String artwork;
}
