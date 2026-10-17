import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_player/src/platform_interface/audio_player_platform_interface.dart';
import 'package:audio_player/src/player_exception.dart';
import 'package:audio_player/src/player_state.dart';
import 'package:audio_player/src/sequence_state.dart';
import 'package:audio_player/src/shuffle_order.dart';
import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart' show experimental;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/synchronized.dart';

part 'audio_effects.dart';
part 'internal/idle_audio_player.dart';
part 'internal/proxy_http_server.dart';
part 'internal/utils.dart';
part 'load_configuration.dart';
part 'metadata.dart';
part 'platform_options.dart';
part 'sources/audio_source.dart';
part 'sources/composite_audio_source.dart';
part 'sources/stream_audio_source.dart';

AudioPlayerPlatform? _pluginPlatformCache;

AudioPlayerPlatform get _pluginPlatform {
  final pluginPlatform = AudioPlayerPlatform.instance;
  // If this is a new FlutterEngine or if we've just hot restarted an existing
  // FlutterEngine...
  if (_pluginPlatformCache == null) {
    // Dispose of all existing players within this FlutterEngine. This helps to
    // shut down existing players on a hot restart. TODO: Remove this hack once
    // https://github.com/flutter/flutter/issues/10437 is implemented.
    try {
      unawaited(pluginPlatform.disposeAllPlayers(DisposeAllPlayersRequest()));
    } catch (e) {
      // Silently ignore if a platform doesn't support this method.
    }
    _pluginPlatformCache = pluginPlatform;
  }
  return pluginPlatform;
}

/// An audio player that plays a gapless playlist of [AudioSource]s.
///
/// ```
/// final player = AudioPlayer();
/// await player.setUrl('https://foo.com/bar.mp3');
/// player.play();
/// await player.pause();
/// await player.setClip(start: Duration(seconds: 10), end: Duration(seconds: 20));
/// await player.play();
/// await player.setUrl('https://foo.com/baz.mp3');
/// await player.seek(Duration(minutes: 5));
/// player.play();
/// await player.pause();
/// await player.dispose();
/// ```
///
/// You must call [stop] or [dispose] to release the resources used by this
/// player, including any temporary files created to cache assets.
class AudioPlayer {
  /// Creates an [AudioPlayer].
  ///
  /// Apps requesting remote URLs should set the [_userAgent] parameter which
  /// will be set as the `user-agent` header on all requests (except on web
  /// where the browser's user agent will be used) to identify the client. If
  /// unspecified, a platform-specific default will be supplied.
  ///
  /// Request headers including `user-agent` are sent by default via a local
  /// HTTP proxy which requires non-HTTPS support to be enabled (see the README
  /// page for setup instructions). Alternatively, you can set
  /// [_useProxyForRequestHeaders] to `false` to allow supported platforms to
  /// send the request headers directly without use of the proxy. On iOS/macOS,
  /// this will use the `AVURLAssetHTTPUserAgentKey` on iOS 16 and above, and
  /// macOS 13 and above, if `user-agent` is the only header used. Otherwise,
  /// the `AVURLAssetHTTPHeaderFieldsKey` key will be used. On Android, this
  /// will use ExoPlayer's `setUserAgent` and `setDefaultRequestProperties`.
  /// For Linux/Windows federated platform implementations, refer to the
  /// documentation for that implementation's support.
  ///
  /// The player will automatically pause/duck and resume/unduck when audio
  /// interruptions occur (e.g. a phone call) or when headphones are unplugged.
  /// If you wish to handle audio interruptions manually, set
  /// [handleInterruptions] to `false` and interface directly with the audio
  /// session via the [audio_session](https://pub.dev/packages/audio_session)
  /// package. If you do not wish audio_player to automatically activate the audio
  /// session when playing audio, set [_handleAudioSessionActivation] to `false`.
  /// If you do not want audio_player to respect the global
  /// [AndroidAudioAttributes] configured by audio_session, set
  /// [androidApplyAudioAttributes] to `false`.
  ///
  /// The default audio loading and buffering behaviour can be configured via
  /// the [_audioLoadConfiguration] parameter.
  ///
  /// [useLazyPreparation] specifies whether audio sources will be loaded lazily
  /// in preparation to be played. Set this to `false` to make all audio
  /// sources load eagerly in advance.
  ///
  /// [shuffleOrder] determines the playback order (defaulting to
  /// [DefaultShuffleOrder]) when [shuffleModeEnabled] is `true`,
  ///
  /// When [maxSkipsOnError] is set, the player will automatically skip to the
  /// next audio source on load errors, and will give up after [maxSkipsOnError]
  /// attempts. This is supported on Android, iOS and web. For other platforms,
  /// check the documentation of the respective platform implementation.
  ///
  /// [_androidAudioOffloadPreferences] specifies whether audio offload is enabled
  /// on Android.
  new({
    this._userAgent,
    bool handleInterruptions = true,
    bool androidApplyAudioAttributes = true,
    this._handleAudioSessionActivation = true,
    this._audioLoadConfiguration,
    AudioPipeline? audioPipeline,
    this._androidAudioOffloadPreferences,
    this._useProxyForRequestHeaders = true,
    bool useLazyPreparation = true,
    ShuffleOrder? shuffleOrder,
    int maxSkipsOnError = 0,
  }) : _id = _generateId(),
       _androidApplyAudioAttributes = androidApplyAudioAttributes && _isAndroid(),
       _audioPipeline = audioPipeline ?? AudioPipeline(),
       _playlist = _PlaylistAudioSource(
         children: [],
         useLazyPreparation: useLazyPreparation,
         shuffleOrder: shuffleOrder,
       ) {
    _audioPipeline._setup(this);
    _playlist._onAttach(this);
    if (_audioLoadConfiguration?.darwinLoadControl != null) {
      _automaticallyWaitsToMinimizeStalling =
          _audioLoadConfiguration!.darwinLoadControl!.automaticallyWaitsToMinimizeStalling;
    }
    _playbackEventPipe = _playbackEventSubject.addStream(
      playerEventStream.map((event) => event.playbackEvent).distinct(),
    );
    unawaited(_playingSubject.addStream(playerEventStream.map((event) => event.playing).distinct()));
    unawaited(_durationSubject.addStream(playbackEventStream.map((event) => event.duration).distinct()));
    unawaited(_processingStateSubject.addStream(playbackEventStream.map((event) => event.processingState).distinct()));
    unawaited(
      _bufferedPositionSubject.addStream(playbackEventStream.map((event) => event.bufferedPosition).distinct()),
    );
    unawaited(_icyMetadataSubject.addStream(playbackEventStream.map((event) => event.icyMetadata).distinct()));
    _positionDiscontinuitySubscription = playbackEventStream
        .map(
          (event) => (
            event,
            (sequence.isNotEmpty && event.currentIndex != null && event.currentIndex! < sequence.length)
                ? sequence[event.currentIndex!]
                : null,
          ),
        )
        .pairwise()
        .listen((rec) {
          if (_seeking) {
            return;
          }
          final [(prevEvent, prevSource), (currEvent, currSource)] = rec.toList();
          if (prevSource == null || currSource == null) {
            return;
          }
          if (currSource._id != prevSource._id) {
            // If we've changed item without seeking, it must be an autoAdvance.
            _positionDiscontinuitySubject.add(
              PositionDiscontinuity(PositionDiscontinuityReason.autoAdvance, prevEvent, currEvent),
            );
          } else {
            // If the item is the same, try to determine whether we have looped
            // back.
            if (loopMode == LoopMode.off) {
              return;
            }
            final prevPos = _getPositionFor(prevEvent);
            final currPos = _getPositionFor(currEvent);
            // if (loopMode != LoopMode.one) return;
            if (currPos >= prevPos) {
              return;
            }
            if (currPos >= const Duration(milliseconds: 300)) {
              return;
            }
            final duration = this.duration;
            if (duration != null && prevPos < duration * 0.6) {
              return;
            }
            if (duration == null && currPos - prevPos < const Duration(seconds: 1)) {
              return;
            }
            _positionDiscontinuitySubject.add(
              PositionDiscontinuity(PositionDiscontinuityReason.autoAdvance, prevEvent, currEvent),
            );
          }
        });
    _currentIndexSubscription = playbackEventStream.listen(
      (event) => _sequenceStateSubject.add(sequenceState.copyWith(currentIndex: event.currentIndex)),
    );
    unawaited(_currentIndexSubject.addStream(sequenceStateStream.map((sequenceState) => sequenceState.currentIndex)));
    unawaited(_sequenceSubject.addStream(sequenceStateStream.map((sequenceState) => sequenceState.sequence)));
    unawaited(
      _shuffleIndicesSubject.addStream(sequenceStateStream.map((sequenceState) => sequenceState.shuffleIndices)),
    );
    unawaited(
      _shuffleModeEnabledSubject.addStream(
        sequenceStateStream.map((sequenceState) => sequenceState.shuffleModeEnabled),
      ),
    );
    unawaited(_loopModeSubject.addStream(sequenceStateStream.map((sequenceState) => sequenceState.loopMode)));

    unawaited(
      _androidAudioSessionIdSubject.addStream(
        playbackEventStream.map((event) => event.androidAudioSessionId).distinct(),
      ),
    );

    unawaited(
      _errorSubject.addStream(
        playbackEventStream
            .map((event) => (code: event.errorCode, message: event.errorMessage, index: event.currentIndex))
            .distinct()
            .where((error) => error.code != null)
            .map((error) => PlayerException(error.code!, error.message, error.index)),
      ),
    );
    unawaited(
      _playerStateSubject.addStream(
        playerEventStream
            .map((event) => PlayerState(playing: event.playing, processingState: event.playbackEvent.processingState))
            .distinct(),
      ),
    );
    unawaited(_setPlatformActive(false, force: true)?.catchError((_) => null));
    // Respond to changes to AndroidAudioAttributes configuration.
    if (androidApplyAudioAttributes && _isAndroid()) {
      unawaited(
        AudioSession.instance.then((audioSession) {
          _androidAudioAttributesSubscription = audioSession.configurationStream
              .map((conf) => conf.androidAudioAttributes)
              .where((attributes) => attributes != null)
              .cast<AndroidAudioAttributes>()
              .distinct()
              .listen(setAndroidAudioAttributes);
        }),
      );
    }
    if (handleInterruptions) {
      unawaited(
        AudioSession.instance.then((session) {
          _becomingNoisyEventSubscription = session.becomingNoisyEventStream.listen((_) {
            unawaited(pause());
          });
          _interruptionEventSubscription = session.interruptionEventStream.listen((event) {
            if (event.begin) {
              switch (event.type) {
                case AudioInterruptionType.duck:
                  assert(_isAndroid(), 'Ducking interruptions only occur on Android.');
                  if (session.androidAudioAttributes!.usage == AndroidAudioUsage.game) {
                    unawaited(setVolume(volume / 2));
                  }
                  _playInterrupted = false;
                case AudioInterruptionType.pause:
                case AudioInterruptionType.unknown:
                  if (playing) {
                    unawaited(pause());
                    // Although pause is async and sets _playInterrupted = false,
                    // this is done in the sync portion.
                    _playInterrupted = true;
                  }
              }
            } else {
              switch (event.type) {
                case AudioInterruptionType.duck:
                  assert(_isAndroid(), 'Ducking interruptions only occur on Android.');
                  unawaited(setVolume(min(1, volume * 2)));
                  _playInterrupted = false;
                case AudioInterruptionType.pause:
                  if (_playInterrupted) {
                    unawaited(play());
                  }
                  _playInterrupted = false;
                case AudioInterruptionType.unknown:
                  _playInterrupted = false;
              }
            }
          });
        }),
      );
    }
    if (maxSkipsOnError > 0) {
      var consecutiveErrorCount = 0;
      _errorsSubscription = errorStream.listen((error) {
        if (audioSources.length > 1 && consecutiveErrorCount < maxSkipsOnError && hasNext) {
          consecutiveErrorCount++;
          scheduleMicrotask(() => seekToNext().catchError((e, st) {}));
        } else {
          scheduleMicrotask(() => pause().catchError((e, st) {}));
        }
      });
      _errorsResetSubscription = processingStateStream.listen((state) {
        if (state == ProcessingState.ready && consecutiveErrorCount > 0) {
          consecutiveErrorCount = 0;
        }
      });
    }
    unawaited(_removeOldAssetCacheDir());
  }
  static String _generateId() => _generateUuidV4();
  final _lock = Lock(reentrant: true);
  Future<void>? _playbackEventPipe;

  /// The user agent to set on all HTTP requests.
  final String? _userAgent;

  /// Whether to use the proxy server to send request headers.
  final bool _useProxyForRequestHeaders;

  final AudioLoadConfiguration? _audioLoadConfiguration;

  final AndroidAudioOffloadPreferences? _androidAudioOffloadPreferences;

  /// This is `true` when the audio player needs to engage the native platform
  /// side of the plugin to decode or play audio, and is `false` when the native
  /// resources are not needed (i.e. after initial instantiation and after [stop]).
  bool _active = false;

  /// This is set to [_nativePlatform] when [_active] is `true` and
  /// [_idlePlatform] otherwise.
  late Future<AudioPlayerInstancePlatform> _platform;

  /// Reflects the current platform immediately after it is set.
  AudioPlayerInstancePlatform? _platformValue;

  /// The interface to the native portion of the plugin. This will be disposed
  /// and set to `null` when not in use.
  Future<AudioPlayerInstancePlatform>? _nativePlatform;

  /// A pure Dart implementation of the platform interface for use when the
  /// native platform is not needed.
  _IdleAudioPlayer? _idlePlatform;

  /// The subscription to the event channel of the current platform
  /// implementation. When switching between active and inactive modes, this is
  /// used to cancel the subscription to the previous platform's events and
  /// subscribe to the new platform's events.
  StreamSubscription<PlaybackEventMessage>? _playbackEventSubscription;

  /// The subscription to the data event channel of the current platform
  /// implementation. When switching between active and inactive modes, this is
  /// used to cancel the subscription to the previous platform's events and
  /// subscribe to the new platform's events.
  StreamSubscription<PlayerDataMessage>? _playerDataSubscription;

  StreamSubscription<AndroidAudioAttributes>? _androidAudioAttributesSubscription;
  StreamSubscription<void>? _becomingNoisyEventSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionEventSubscription;
  StreamSubscription<void>? _positionDiscontinuitySubscription;
  StreamSubscription<void>? _currentIndexSubscription;
  StreamSubscription<void>? _errorsSubscription;
  StreamSubscription<void>? _errorsResetSubscription;

  String? _id;
  final _proxy = _ProxyHttpServer();

  final _PlaylistAudioSource _playlist;
  final Map<String, AudioSource> _audioSources = {};
  bool _disposed = false;
  _PluginLoadRequest? _pluginLoadRequest;
  final AudioPipeline _audioPipeline;

  Future<Duration?>? _loadFuture;
  final _shuffleIndicesInv = <int>[];

  final _playerEventSubject = BehaviorSubject<PlayerEvent>.seeded(PlayerEvent(), sync: true);

  final _playbackEventSubject = BehaviorSubject<PlaybackEvent>.seeded(PlaybackEvent(), sync: true);

  // derived from playbackEventStream
  final _processingStateSubject = BehaviorSubject<ProcessingState>.seeded(ProcessingState.idle);
  final _durationSubject = BehaviorSubject<Duration?>.seeded(null);
  final _bufferedPositionSubject = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _icyMetadataSubject = BehaviorSubject<IcyMetadata?>.seeded(null);
  final _androidAudioSessionIdSubject = BehaviorSubject<int?>.seeded(null);
  final _errorSubject = PublishSubject<PlayerException>();

  // independent streams
  final _playingSubject = BehaviorSubject.seeded(false);
  final _volumeSubject = BehaviorSubject<double>.seeded(1);
  final _speedSubject = BehaviorSubject<double>.seeded(1);
  final _pitchSubject = BehaviorSubject<double>.seeded(1);
  final _skipSilenceEnabledSubject = BehaviorSubject.seeded(false);

  final _positionDiscontinuitySubject = PublishSubject<PositionDiscontinuity>(sync: true);

  final _sequenceStateSubject = BehaviorSubject<SequenceState>.seeded(
    SequenceState(
      sequence: [],
      currentIndex: null,
      shuffleIndices: [],
      shuffleModeEnabled: false,
      loopMode: LoopMode.off,
    ),
    sync: true,
  );

  // derived from sequenceStateStream
  final _sequenceSubject = BehaviorSubject.seeded(<IndexedAudioSource>[]);
  final _shuffleIndicesSubject = BehaviorSubject.seeded(<int>[]);
  final _currentIndexSubject = BehaviorSubject<int?>.seeded(null);
  final _loopModeSubject = BehaviorSubject.seeded(LoopMode.off);
  final _shuffleModeEnabledSubject = BehaviorSubject.seeded(false);

  final _playerStateSubject = BehaviorSubject<PlayerState>.seeded(
    const PlayerState(playing: false, processingState: ProcessingState.idle),
  );

  var _seeking = false;

  // Lives as long as the position stream it pipes (see createPositionStream).
  // ignore: close_sinks
  BehaviorSubject<Duration>? _positionSubject;
  bool _automaticallyWaitsToMinimizeStalling = true;
  bool _canUseNetworkResourcesForLiveStreamingWhilePaused = false;
  double _preferredPeakBitRate = 0;
  bool _allowsExternalPlayback = false;
  bool _playInterrupted = false;
  bool _platformLoading = false;
  AndroidAudioAttributes? _androidAudioAttributes;
  WebCrossOrigin? _webCrossOrigin;
  String _webSinkId = '';
  final bool _androidApplyAudioAttributes;
  final bool _handleAudioSessionActivation;

  /// Counts how many times [_setPlatformActive] is called.
  int _activationCount = 0;

  /// Old versions of audio_player used an asset caching system that created a
  /// separate cache file per asset per player instance, and was highly
  /// dependent on the app calling [dispose] to clean up afterwards. If the app
  /// is upgrading from an old version of audio_player, this will delete the old
  /// cache directory.
  Future<void> _removeOldAssetCacheDir() async {
    if (kIsWeb) {
      return;
    }
    try {
      final oldAssetCacheDir = Directory(p.join((await getTemporaryDirectory()).path, 'audio_player_asset_cache'));
      if (oldAssetCacheDir.existsSync()) {
        try {
          oldAssetCacheDir.deleteSync(recursive: true);
        } catch (e) {
          // Best-effort cleanup; there is no logger to report this failure to.
          // ignore: avoid_print
          print('Failed to delete old asset cache dir: $e');
        }
      }
    } catch (e) {
      // There is no temporary directory for this platform.
    }
  }

  /// The first [AudioSource] in the playlist, if any.
  AudioSource? get audioSource => _playlist.children.firstOrNull;

  /// The latest [PlayerEvent].
  PlayerEvent get playerEvent => _playerEventSubject.nullableValue!;

  /// A stream of [PlayerEvent]s.
  Stream<PlayerEvent> get playerEventStream => _playerEventSubject.stream;

  /// The latest [PlaybackEvent].
  PlaybackEvent get playbackEvent => _playerEventSubject.nullableValue!.playbackEvent;

  /// A stream of [PlaybackEvent]s.
  Stream<PlaybackEvent> get playbackEventStream => _playbackEventSubject.stream;

  /// The duration of the current audio or `null` if unknown.
  Duration? get duration => playbackEvent.duration;

  /// The duration of the current audio.
  Stream<Duration?> get durationStream => _durationSubject.stream.distinct();

  /// The current [ProcessingState].
  ProcessingState get processingState => playbackEvent.processingState;

  /// A stream of [ProcessingState]s.
  Stream<ProcessingState> get processingStateStream => _processingStateSubject.stream.distinct();

  /// Whether the player is playing.
  bool get playing => _playerEventSubject.nullableValue!.playing;

  /// A stream of changing [playing] states.
  Stream<bool> get playingStream => _playingSubject.stream.distinct();

  /// The current volume of the player.
  double get volume => _volumeSubject.nullableValue!;

  /// A stream of [volume] changes.
  ValueStream<double> get volumeStream => _volumeSubject.stream;

  /// The current speed of the player.
  double get speed => _speedSubject.nullableValue!;

  /// A stream of current speed values.
  ValueStream<double> get speedStream => _speedSubject.stream;

  /// The current pitch factor of the player.
  double get pitch => _pitchSubject.nullableValue!;

  /// A stream of current pitch factor values.
  ValueStream<double> get pitchStream => _pitchSubject.stream;

  /// The current skipSilenceEnabled factor of the player.
  bool get skipSilenceEnabled => _skipSilenceEnabledSubject.nullableValue!;

  /// A stream of current skipSilenceEnabled factor values.
  Stream<bool> get skipSilenceEnabledStream => _skipSilenceEnabledSubject.stream;

  /// The position up to which buffered audio is available.
  Duration get bufferedPosition => _bufferedPositionSubject.nullableValue ?? Duration.zero;

  /// A stream of buffered positions.
  Stream<Duration> get bufferedPositionStream => _bufferedPositionSubject.stream.distinct();

  /// The latest ICY metadata received through the audio source, or `null` if no
  /// metadata is available.
  IcyMetadata? get icyMetadata => playbackEvent.icyMetadata;

  /// A stream of ICY metadata received through the audio source.
  Stream<IcyMetadata?> get icyMetadataStream => _icyMetadataSubject.stream.distinct();

  /// The current player state containing only the processing and playing
  /// states.
  PlayerState get playerState =>
      _playerStateSubject.nullableValue ?? const PlayerState(playing: false, processingState: ProcessingState.idle);

  /// A stream of [PlayerState]s.
  Stream<PlayerState> get playerStateStream => _playerStateSubject.stream;

  /// The current sequence of indexed audio sources.
  List<IndexedAudioSource> get sequence => _sequenceSubject.nullableValue!;

  /// A stream broadcasting the current sequence of indexed audio sources.
  Stream<List<IndexedAudioSource>> get sequenceStream => _sequenceSubject.stream;

  /// The current shuffled sequence of indexed audio sources.
  List<int> get shuffleIndices => _shuffleIndicesSubject.nullableValue!;

  /// A stream broadcasting the current shuffled sequence of indexed audio
  /// sources.
  Stream<List<int>> get shuffleIndicesStream => _shuffleIndicesSubject.stream;

  /// The index of the current [IndexedAudioSource] in [sequence], or `null` if
  /// [sequence] is empty.
  int? get currentIndex => _currentIndexSubject.nullableValue;

  /// A stream broadcasting the current index.
  Stream<int?> get currentIndexStream => _currentIndexSubject.stream;

  /// The current [SequenceState].
  SequenceState get sequenceState => _sequenceStateSubject.nullableValue!;

  /// A stream broadcasting the current [SequenceState].
  Stream<SequenceState> get sequenceStateStream => _sequenceStateSubject.stream;

  /// Whether there is another item after the current index.
  bool get hasNext => nextIndex != null;

  /// Whether there is another item before the current index.
  bool get hasPrevious => previousIndex != null;

  /// Returns [shuffleIndices] if [shuffleModeEnabled] is `true`, otherwise
  /// returns the unshuffled indices.
  List<int> get effectiveIndices => shuffleModeEnabled ? shuffleIndices : List.generate(sequence.length, (i) => i);

  List<int> get _effectiveIndicesInv =>
      shuffleModeEnabled ? _shuffleIndicesInv : List.generate(sequence.length, (i) => i);

  /// The index of the next item to be played, or `null` if there is no next
  /// item.
  int? get nextIndex => _getRelativeIndex(1);

  /// The index of the previous item in play order, or `null` if there is no
  /// previous item.
  int? get previousIndex => _getRelativeIndex(-1);

  int? _getRelativeIndex(int offset) {
    if (_playlist.children.isEmpty || currentIndex == null) {
      return null;
    }
    if (loopMode == LoopMode.one) {
      return currentIndex;
    }
    final effectiveIndices = this.effectiveIndices;
    if (effectiveIndices.isEmpty) {
      return null;
    }
    final effectiveIndicesInv = _effectiveIndicesInv;
    if (currentIndex! >= effectiveIndicesInv.length) {
      return null;
    }
    final invPos = effectiveIndicesInv[currentIndex!];
    var newInvPos = invPos + offset;
    if (newInvPos >= effectiveIndices.length || newInvPos < 0) {
      if (loopMode == LoopMode.all) {
        newInvPos %= effectiveIndices.length;
      } else {
        return null;
      }
    }
    final result = effectiveIndices[newInvPos];
    return result;
  }

  /// The current loop mode.
  LoopMode get loopMode => _loopModeSubject.nullableValue!;

  /// A stream of [LoopMode]s.
  Stream<LoopMode> get loopModeStream => _loopModeSubject.stream;

  /// Whether shuffle mode is currently enabled.
  bool get shuffleModeEnabled => _shuffleModeEnabledSubject.nullableValue!;

  /// A stream of the shuffle mode status.
  Stream<bool> get shuffleModeEnabledStream => _shuffleModeEnabledSubject.stream;

  /// The current Android AudioSession ID or `null` if not set.
  int? get androidAudioSessionId => playbackEvent.androidAudioSessionId;

  /// Broadcasts the current Android AudioSession ID or `null` if not set.
  Stream<int?> get androidAudioSessionIdStream => _androidAudioSessionIdSubject.stream;

  /// A stream of errors broadcast by the player.
  Stream<PlayerException> get errorStream => _errorSubject.stream;

  /// A stream broadcasting every position discontinuity.
  Stream<PositionDiscontinuity> get positionDiscontinuityStream => _positionDiscontinuitySubject.stream;

  /// Whether the player should automatically delay playback in order to
  /// minimize stalling. (iOS 10.0 or later only)
  bool get automaticallyWaitsToMinimizeStalling => _automaticallyWaitsToMinimizeStalling;

  /// Whether the player can use the network for live streaming while paused on
  /// iOS/macOS.
  bool get canUseNetworkResourcesForLiveStreamingWhilePaused => _canUseNetworkResourcesForLiveStreamingWhilePaused;

  /// The preferred peak bit rate (in bits per second) of bandwidth usage on iOS/macOS.
  double get preferredPeakBitRate => _preferredPeakBitRate;

  /// Whether the player allows external playback on iOS/macOS, defaults to
  /// false.
  bool get allowsExternalPlayback => _allowsExternalPlayback;

  /// The `crossorigin` attribute set the `<audio>` element backing this player
  /// instance on web.
  WebCrossOrigin? get webCrossOrigin => _webCrossOrigin;

  /// The current sink ID of the `<audio>` element backing this instance on web.
  String get webSinkId => _webSinkId;

  /// The current position of the player.
  Duration get position => _getPositionFor(playbackEvent);

  Duration _getPositionFor(PlaybackEvent playbackEvent) {
    if (playing && processingState == ProcessingState.ready) {
      final result = playbackEvent.updatePosition + (DateTime.now().difference(playbackEvent.updateTime)) * speed;
      return playbackEvent.duration == null || result <= playbackEvent.duration! ? result : playbackEvent.duration!;
    } else {
      return playbackEvent.updatePosition;
    }
  }

  /// A stream tracking the current position of this player, suitable for
  /// animating a seek bar. To ensure a smooth animation, this stream emits
  /// values more frequently on short items where the seek bar moves more
  /// quickly, and less frequently on long items where the seek bar moves more
  /// slowly. The interval between each update will be no quicker than once
  /// every 16ms and no slower than once every 200ms.
  ///
  /// See [createPositionStream] for more control over the stream parameters.
  Stream<Duration> get positionStream {
    if (_positionSubject == null) {
      _positionSubject = BehaviorSubject<Duration>(onCancel: () => _positionSubject = null);
      if (!_disposed) {
        unawaited(_positionSubject!.addStream(createPositionStream(minPeriod: const Duration(milliseconds: 16))));
      }
    }
    return _positionSubject!.stream;
  }

  /// Creates a new stream periodically tracking the current position of this
  /// player. The stream will aim to emit [steps] position updates from the
  /// beginning to the end of the current audio source, at intervals of
  /// [duration] / [steps]. This interval will be clipped between [minPeriod]
  /// and [maxPeriod]. This stream will not emit values while audio playback is
  /// paused or stalled.
  ///
  /// Note: each time this method is called, a new stream is created. If you
  /// intend to use this stream multiple times, you should hold a reference to
  /// the returned stream and close it once you are done.
  Stream<Duration> createPositionStream({
    int steps = 800,
    Duration minPeriod = const Duration(milliseconds: 200),
    Duration maxPeriod = const Duration(milliseconds: 200),
  }) {
    assert(minPeriod <= maxPeriod, 'minPeriod must not exceed maxPeriod.');
    assert(minPeriod > Duration.zero, 'minPeriod must be positive.');
    final controller = StreamController<Duration>.broadcast();
    if (_disposed) {
      return controller.stream;
    }

    Duration duration() => this.duration ?? Duration.zero;
    Duration step() {
      var s = duration() ~/ steps;
      if (s < minPeriod) {
        s = minPeriod;
      }
      if (s > maxPeriod) {
        s = maxPeriod;
      }
      return s;
    }

    Timer? currentTimer;
    StreamSubscription<PlayerEvent>? playerEventSubscription;
    void yieldPosition(Timer timer) {
      if (controller.isClosed || _durationSubject.isClosed) {
        timer.cancel();
        unawaited(playerEventSubscription?.cancel());
        if (!controller.isClosed) {
          // This will in turn close _positionSubject.
          unawaited(controller.close());
        }
        return;
      }
      if (playing) {
        controller.add(position);
      }
    }

    playerEventSubscription = playerEventStream.listen((event) {
      controller.add(position);
      currentTimer?.cancel();
      if (playing) {
        currentTimer = Timer.periodic(step(), yieldPosition);
      }
    });
    return controller.stream.distinct();
  }

  /// Convenience method to set the audio source to a URL with optional headers,
  /// preloaded by default, with an initial position of zero by default.
  /// If headers are set, audio_player will create a cleartext local HTTP proxy on
  /// your device to forward HTTP requests with headers included.
  ///
  /// This is equivalent to:
  ///
  /// ```
  /// setAudioSource(AudioSource.uri(Uri.parse(url), headers: headers, tag: tag),
  ///     initialPosition: Duration.zero, preload: true);
  /// ```
  ///
  /// See [setAudioSources] for a detailed explanation of the options.
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    Object? tag,
  }) => setAudioSource(
    AudioSource.uri(Uri.parse(url), headers: headers, tag: tag),
    initialPosition: initialPosition,
    preload: preload,
  );

  /// Convenience method to set the audio source to a file, preloaded by
  /// default, with an initial position of zero by default.
  ///
  /// This is equivalent to:
  ///
  /// ```
  /// setAudioSource(AudioSource.uri(Uri.file(filePath), tag: tag),
  ///     initialPosition: Duration.zero, preload: true);
  /// ```
  ///
  /// See [setAudioSources] for a detailed explanation of the options.
  Future<Duration?> setFilePath(String filePath, {Duration? initialPosition, bool preload = true, Object? tag}) =>
      setAudioSource(
        AudioSource.file(filePath, tag: tag),
        initialPosition: initialPosition,
        preload: preload,
      );

  /// Convenience method to set the audio source to an asset, preloaded by
  /// default, with an initial position of zero by default.
  ///
  /// For assets within the same package, this is equivalent to:
  ///
  /// ```
  /// setAudioSource(AudioSource.uri(Uri.parse('asset:///$assetPath'), tag: tag),
  ///     initialPosition: Duration.zero, preload: true);
  /// ```
  ///
  /// If the asset is to be loaded from a different package, the [package]
  /// parameter must be given to specify the package name.
  ///
  /// See [setAudioSources] for a detailed explanation of the options.
  Future<Duration?> setAsset(
    String assetPath, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    Object? tag,
  }) => setAudioSource(
    AudioSource.asset(assetPath, package: package, tag: tag),
    initialPosition: initialPosition,
    preload: preload,
  );

  /// Clears the playlist and adds the given [audioSource].
  ///
  /// This is equivalent to:
  ///
  /// ```
  /// setAudioSources([source], initialIndex: 0, initialPosition: Duration.zero,
  ///     preload: true);
  /// ```
  ///
  /// See [setAudioSources] for a detailed explanation of the options.
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) => setAudioSources([audioSource], preload: preload, initialIndex: initialIndex, initialPosition: initialPosition);

  /// Clears the playlist and adds the given [audioSources].
  ///
  /// By default, this method will immediately start loading the initial
  /// [AudioSource] and return its duration as soon as it is known, or `null` if
  /// that information is unavailable. Set [preload] to `false` if you would
  /// prefer to delay loading until some later point, either via an explicit
  /// call to [load] or via a call to [play] which implicitly loads the audio.
  /// If [preload] is `false`, a `null` duration will be returned. Note that the
  /// [preload] option will automatically be assumed as `true` if `playing` is
  /// currently `true`.
  ///
  /// Optionally specify [initialPosition] and [initialIndex] to seek to an
  /// initial position within a particular item (defaulting to position zero of
  /// the first item).
  ///
  /// When [preload] is `true`, this method may throw:
  ///
  /// * [PlayerException] if the initial audio source was unable to be loaded.
  /// * [PlayerInterruptedException] if another invocation of this method
  /// interrupted this invocation.
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    _pluginLoadRequest?.interrupted = true;
    if (_disposed) {
      return null;
    }
    final loadRequest = _pluginLoadRequest = _PluginLoadRequest(
      audioSources: audioSources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder ?? DefaultShuffleOrder(),
    );
    await _playlist._init(audioSources, loadRequest.shuffleOrder);
    loadRequest.checkInterruption();
    Duration? duration;
    if (preload || playing) {
      duration = await load();
    } else {
      await _setPlatformActive(false)?.catchError((_) => null);
    }
    loadRequest.checkInterruption();
    return duration;
  }

  /// Starts loading the playlist and returns the audio duration of the initial
  /// [AudioSource] in the playlist as soon as it is known, or `null` if
  /// unavailable. This method does nothing if the playlist is empty.
  ///
  /// This method throws:
  ///
  /// * [PlayerException] if the audio source was unable to be loaded.
  /// * [PlayerInterruptedException] if another invocation of [setAudioSources]
  /// interrupted this invocation.
  Future<Duration?> load() async {
    if (_disposed) {
      return null;
    }
    final pluginLoadRequest = _pluginLoadRequest;
    if (_playlist.children.isEmpty) {
      return null;
    }
    if (_active) {
      return await _load(await _platform, _playlist, initialSeekValues: pluginLoadRequest?.initialSeekValues);
    } else {
      // This will implicitly load the current audio source.
      return await _setPlatformActive(true);
    }
  }

  /// Adds [audioSource] to the end of the playlist.
  Future<void> addAudioSource(AudioSource audioSource) => _playlist.add(audioSource);

  /// Inserts [audioSource] into the playlist at [index].
  Future<void> insertAudioSource(int index, AudioSource audioSource) => _playlist.insert(index, audioSource);

  /// Adds [audioSources] to the end of the playlist.
  Future<void> addAudioSources(List<AudioSource> audioSources) => _playlist.addAll(audioSources);

  /// Inserts [audioSources] into the playlist at [index].
  Future<void> insertAudioSources(int index, List<AudioSource> audioSources) =>
      _playlist.insertAll(index, audioSources);

  /// Removes the [AudioSource] at [index] from the playlist.
  Future<void> removeAudioSourceAt(int index) => _playlist.removeAt(index);

  /// Removes the [AudioSource]s from index [start] to [end] from the playlist.
  Future<void> removeAudioSourceRange(int start, int end) => _playlist.removeRange(start, end);

  /// Moves the [AudioSource] in the playlist at [currentIndex] to [newIndex].
  Future<void> moveAudioSource(int currentIndex, int newIndex) => _playlist.move(currentIndex, newIndex);

  /// Clears the playlist.
  Future<void> clearAudioSources() => _playlist.clear();

  /// The playlist.
  List<AudioSource> get audioSources => _playlist.children;

  Future<void> _broadcastSequence({bool sequenceChanged = true}) async {
    _sequenceStateSubject.add(
      sequenceState.copyWith(
        sequence: sequenceChanged ? _playlist.sequence : sequenceState.sequence,
        shuffleIndices: _playlist.shuffleIndices,
      ),
    );
    final shuffleIndicesLength = shuffleIndices.length;
    if (_shuffleIndicesInv.length > shuffleIndicesLength) {
      _shuffleIndicesInv.removeRange(shuffleIndicesLength, _shuffleIndicesInv.length);
    } else if (_shuffleIndicesInv.length < shuffleIndicesLength) {
      _shuffleIndicesInv.addAll(List.filled(shuffleIndicesLength - _shuffleIndicesInv.length, 0));
    }
    for (var i = 0; i < shuffleIndicesLength; i++) {
      _shuffleIndicesInv[shuffleIndices[i]] = i;
    }
    // Allow this event to propagate to derived streams.
    await currentIndexStream.firstWhere((i) => i == sequenceState.currentIndex);
  }

  void _registerAudioSource(AudioSource source) {
    _audioSources[source._id] = source;
  }

  Future<Duration?> _load(
    AudioPlayerInstancePlatform platform,
    _PlaylistAudioSource source, {
    _InitialSeekValues? initialSeekValues,
  }) async {
    final pluginLoadRequest = _pluginLoadRequest;
    final activationNumber = _activationCount;
    void checkInterruption() {
      if (_activationCount != activationNumber || pluginLoadRequest != _pluginLoadRequest) {
        // the platform has changed since we started loading, so abort.
        throw PlayerInterruptedException('Loading interrupted');
      }
      pluginLoadRequest?.checkInterruption();
    }

    try {
      if (_active) {
        await source._onLoad();
        checkInterruption();
      }
      source._shuffle(initialIndex: initialSeekValues?.index ?? 0);
      await _broadcastSequence();
      checkInterruption();
      _loadFuture = platform
          .load(
            LoadRequest(
              audioSourceMessage: source._toMessage(),
              initialPosition: initialSeekValues?.position,
              initialIndex: initialSeekValues?.index,
            ),
          )
          .then((response) => response.duration);
      final duration = await _loadFuture;
      checkInterruption();
      if (platform != _platformValue) {
        // the platform has changed since we started loading, so abort.
        throw PlayerInterruptedException('Loading interrupted');
      }
      // Wait for loading state to pass.
      await processingStateStream.firstWhere((state) => state != ProcessingState.loading);
      checkInterruption();
      _pluginLoadRequest = null;
      return duration;
    } on PlatformException catch (e, st) {
      Error.throwWithStackTrace(_convertException(e), st);
    }
  }

  /// Clips the current [AudioSource] to the given [start] and [end]
  /// timestamps. If [start] is null, it will be reset to the start of the
  /// original [AudioSource]. If [end] is null, it will be reset to the end of
  /// the original [AudioSource]. This method cannot be called from the
  /// [ProcessingState.idle] state.
  Future<Duration?> setClip({Duration? start, Duration? end, Object? tag}) async {
    if (_disposed) {
      return null;
    }
    final audioSource = _playlist.children.firstOrNull;
    if (_playlist.children.length != 1 || audioSource is! UriAudioSource) {
      throw Exception('Playlist must contain 1 UriAudioSource');
    }
    unawaited(_setPlatformActive(true)?.catchError((_) => null));
    final duration = await _load(
      await _platform,
      start == null && end == null
          ? _playlist
          : _PlaylistAudioSource(
              children: [ClippingAudioSource(child: audioSource, start: start, end: end, tag: tag)],
            ),
    );
    return duration;
  }

  /// Tells the player to play audio at the current [speed] and [volume] as soon
  /// as an audio source is loaded and ready to play. If an audio source has
  /// been set but not preloaded, this method will also initiate the loading.
  /// The [Future] returned by this method completes when the playback completes
  /// or is paused or stopped. If the player is already playing, this method
  /// completes immediately.
  ///
  /// This method causes [playing] to become true, and it will remain true
  /// until [pause] or [stop] is called. This means that if playback completes,
  /// and then you [seek] to an earlier position in the audio, playback will
  /// continue playing from that position. If you instead wish to [pause] or
  /// [stop] playback on completion, you can call either method as soon as
  /// [processingState] becomes [ProcessingState.completed] by listening to
  /// [processingStateStream].
  ///
  /// This method activates the audio session before playback, and will do
  /// nothing if activation of the audio session fails for any reason.
  Future<void> play() async {
    if (_disposed) {
      return;
    }
    if (playing) {
      return;
    }
    _playInterrupted = false;
    // Broadcast to clients immediately, but revert to false if we fail to
    // activate the audio session. This allows setAudioSource to be aware of a
    // prior play request.
    _playerEventSubject.add(
      PlayerEvent(
        playing: true,
        playbackEvent: playbackEvent.copyWith(updatePosition: position, updateTime: DateTime.now()),
      ),
    );
    final playCompleter = Completer<dynamic>();
    final audioSession = await AudioSession.instance;
    if (!_handleAudioSessionActivation || await audioSession.setActive(true)) {
      if (!playing) {
        return;
      }
      // TODO(SunnatilloShavkatov): rewrite this to more cleanly handle simultaneous load/play
      // requests which each may result in platform play requests.
      final requireActive = _playlist.children.isNotEmpty;
      if (requireActive) {
        if (_active) {
          // If the native platform is already active, send it a play request.
          // NOTE: If a load() request happens simultaneously, this may result
          // in two play requests being sent. The platform implementation should
          // ignore the second play request since it is already playing.
          unawaited(_sendPlayRequest(await _platform, playCompleter));
        } else {
          // If the native platform wasn't already active, activating it will
          // implicitly restore the playing state and send a play request.
          unawaited(_setPlatformActive(true, playCompleter: playCompleter)?.catchError((_) => null));
        }
      }
    } else {
      // Revert if we fail to activate the audio session.
      _playerEventSubject.add(playerEvent.copyWith(playing: false));
    }
    await playCompleter.future;
  }

  /// Pauses the currently playing media. This method does nothing if
  /// ![playing].
  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    if (!playing) {
      return;
    }
    _playInterrupted = false;
    // Update local state immediately so that queries aren't surprised.
    _playerEventSubject.add(
      PlayerEvent(
        playbackEvent: playbackEvent.copyWith(updatePosition: position, updateTime: DateTime.now()),
      ),
    );
    // Allow propagation to secondary streams.
    await playingStream.firstWhere((p) => p == playing);
    // TODO(SunnatilloShavkatov): perhaps modify platform side to ensure new state is broadcast
    // before this method returns.
    await (await _platform).pause(PauseRequest());
  }

  Future<void> _sendPlayRequest(AudioPlayerInstancePlatform platform, Completer<void>? playCompleter) async {
    try {
      if (!playing) {
        return; // defensive
      }
      await platform.play(PlayRequest());
      playCompleter?.complete();
    } catch (e, stackTrace) {
      playCompleter?.completeError(e, stackTrace);
    }
  }

  /// Stops playing audio and releases decoders and other native platform
  /// resources needed to play audio. The current audio source state will be
  /// retained and playback can be resumed at a later point in time.
  ///
  /// Use [stop] if the app is done playing audio for now but may need still
  /// want to resume playback later. Use [dispose] when the app is completely
  /// finished playing audio. Use [pause] instead if you would like to keep the
  /// decoders alive so that the app can quickly resume audio playback.
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    final future = _setPlatformActive(false)?.catchError((_) => null);

    _playInterrupted = false;
    // Update local state immediately so that queries aren't surprised.
    _playerEventSubject.add(playerEvent.copyWith(playing: false));
    await future;
  }

  /// Sets the volume of this player, where 1.0 is normal volume.
  Future<void> setVolume(double volume) async {
    if (_disposed) {
      return;
    }
    _volumeSubject.add(volume);
    await (await _platform).setVolume(SetVolumeRequest(volume: volume));
  }

  /// Sets whether silence should be skipped in audio playback. (Currently
  /// Android only).
  Future<void> setSkipSilenceEnabled({required bool enabled}) async {
    if (_disposed) {
      return;
    }
    final previouslyEnabled = skipSilenceEnabled;
    if (enabled == previouslyEnabled) {
      return;
    }
    _skipSilenceEnabledSubject.add(enabled);
    try {
      await (await _platform).setSkipSilence(SetSkipSilenceRequest(enabled: enabled));
    } catch (e) {
      _skipSilenceEnabledSubject.add(previouslyEnabled);
      rethrow;
    }
  }

  /// Sets the playback speed to use when [playing] is `true`, where 1.0 is
  /// normal speed. Note that values in excess of 1.0 may result in stalls if
  /// the playback speed is faster than the player is able to downloaded the
  /// audio.
  Future<void> setSpeed(double speed) async {
    if (_disposed) {
      return;
    }
    _playerEventSubject.add(
      playerEvent.copyWith(
        playbackEvent: playbackEvent.copyWith(updatePosition: position, updateTime: DateTime.now()),
      ),
    );
    _speedSubject.add(speed);
    await (await _platform).setSpeed(SetSpeedRequest(speed: speed));
  }

  /// Sets the factor by which pitch will be shifted.
  Future<void> setPitch(double pitch) async {
    if (_disposed) {
      return;
    }
    _playerEventSubject.add(
      playerEvent.copyWith(
        playbackEvent: playbackEvent.copyWith(updatePosition: position, updateTime: DateTime.now()),
      ),
    );
    _pitchSubject.add(pitch);
    await (await _platform).setPitch(SetPitchRequest(pitch: pitch));
  }

  /// Sets the [LoopMode]. Looping will be gapless on Android, iOS and macOS. On
  /// web, there will be a slight gap at the loop point.
  Future<void> setLoopMode(LoopMode mode) async {
    if (_disposed) {
      return;
    }
    _sequenceStateSubject.add(sequenceState.copyWith(loopMode: mode));
    await (await _platform).setLoopMode(SetLoopModeRequest(loopMode: LoopModeMessage.values[mode.index]));
  }

  /// Sets whether shuffle mode is enabled.
  Future<void> setShuffleModeEnabled({required bool enabled}) async {
    if (_disposed) {
      return;
    }
    _sequenceStateSubject.add(sequenceState.copyWith(shuffleModeEnabled: enabled));
    await (await _platform).setShuffleMode(
      SetShuffleModeRequest(shuffleMode: enabled ? ShuffleModeMessage.all : ShuffleModeMessage.none),
    );
  }

  /// Shuffles the playlist using the [ShuffleOrder] passed into the
  /// constructor, and recursively shuffles each nested [AudioSource]
  /// according to its own [ShuffleOrder].
  Future<void> shuffle() async {
    if (_disposed) {
      return;
    }
    if (_playlist.children.isEmpty) {
      return;
    }
    _playlist._shuffle(initialIndex: currentIndex);
    await _broadcastSequence(sequenceChanged: false);
    await (await _platform).setShuffleOrder(SetShuffleOrderRequest(audioSourceMessage: _playlist._toMessage()));
  }

  /// Sets automaticallyWaitsToMinimizeStalling for AVPlayer in iOS 10.0 or later, defaults to true.
  /// Has no effect on Android clients
  Future<void> setAutomaticallyWaitsToMinimizeStalling({required bool enabled}) async {
    if (_disposed) {
      return;
    }
    _automaticallyWaitsToMinimizeStalling = enabled;
    await (await _platform).setAutomaticallyWaitsToMinimizeStalling(
      SetAutomaticallyWaitsToMinimizeStallingRequest(enabled: enabled),
    );
  }

  /// Sets canUseNetworkResourcesForLiveStreamingWhilePaused on iOS/macOS,
  /// defaults to false.
  Future<void> setCanUseNetworkResourcesForLiveStreamingWhilePaused({required bool enabled}) async {
    if (_disposed) {
      return;
    }
    _canUseNetworkResourcesForLiveStreamingWhilePaused = enabled;
    await (await _platform).setCanUseNetworkResourcesForLiveStreamingWhilePaused(
      SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest(enabled: enabled),
    );
  }

  /// Sets preferredPeakBitRate on iOS/macOS, defaults to true.
  Future<void> setPreferredPeakBitRate(double preferredPeakBitRate) async {
    if (_disposed) {
      return;
    }
    _preferredPeakBitRate = preferredPeakBitRate;
    await (await _platform).setPreferredPeakBitRate(SetPreferredPeakBitRateRequest(bitRate: preferredPeakBitRate));
  }

  /// Sets allowsExternalPlayback on iOS/macOS, defaults to false.
  Future<void> setAllowsExternalPlayback({required bool enabled}) async {
    if (_disposed) {
      return;
    }
    _allowsExternalPlayback = enabled;
    await (await _platform).setAllowsExternalPlayback(
      SetAllowsExternalPlaybackRequest(allowsExternalPlayback: enabled),
    );
  }

  /// Seeks to a particular [position], and optionally to a particular [index]
  /// within [sequence].
  ///
  /// A `null` [position] seeks to the head of a live stream.
  Future<void> seek(Duration? position, {int? index}) async {
    if (_disposed) {
      return;
    }
    _pluginLoadRequest?.resetInitialSeekValues();
    if (processingState == ProcessingState.loading) {
      return;
    }
    try {
      _seeking = true;
      final prevPlaybackEvent = playbackEvent;
      _playerEventSubject.add(
        playerEvent.copyWith(
          playbackEvent: prevPlaybackEvent.copyWith(updatePosition: position, updateTime: DateTime.now()),
        ),
      );
      _positionDiscontinuitySubject.add(
        PositionDiscontinuity(PositionDiscontinuityReason.seek, prevPlaybackEvent, playbackEvent),
      );
      await (await _platform).seek(SeekRequest(position: position, index: index));
      if (playing && !_active) {
        unawaited(_setPlatformActive(true)?.catchError((_) => null));
      }
    } finally {
      _seeking = false;
    }
  }

  /// Seeks to the next item, or does nothing if there is no next item.
  Future<void> seekToNext() async {
    if (hasNext) {
      await seek(Duration.zero, index: nextIndex);
    }
  }

  /// Seeks to the previous item, or does nothing if there is no previous item.
  Future<void> seekToPrevious() async {
    if (hasPrevious) {
      await seek(Duration.zero, index: previousIndex);
    }
  }

  /// Sets the Android audio attributes for this player. Has no effect on other
  /// platforms. This will cause a new Android AudioSession ID to be generated.
  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes audioAttributes) async {
    if (_disposed) {
      return;
    }
    if (!_isAndroid() && !_isUnitTest()) {
      return;
    }
    if (audioAttributes == _androidAudioAttributes) {
      return;
    }
    _androidAudioAttributes = audioAttributes;
    await _internalSetAndroidAudioAttributes(await _platform, audioAttributes);
  }

  Future<void> _internalSetAndroidAudioAttributes(
    AudioPlayerInstancePlatform platform,
    AndroidAudioAttributes audioAttributes,
  ) async {
    if (!_isAndroid() && !_isUnitTest()) {
      return;
    }
    await platform.setAndroidAudioAttributes(
      SetAndroidAudioAttributesRequest(
        contentType: audioAttributes.contentType.index,
        flags: audioAttributes.flags.value,
        usage: audioAttributes.usage.value,
      ),
    );
  }

  /// Sets the `crossorigin` attribute on the `<audio>` element backing this
  /// player instance on web (see
  /// [HTMLMediaElement crossorigin](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/crossOrigin) ).
  ///
  /// If [webCrossOrigin] is null (the initial state), the URL will be fetched
  /// without CORS. If it is `useCredentials`, a CORS request will be made
  /// exchanging credentials (via cookies/certificates/HTTP authentication)
  /// regardless of the origin. If it is 'anonymous', a CORS request will be
  /// made, but credentials are exchanged only if the URL is fetched from the
  /// same origin.
  Future<void> setWebCrossOrigin(WebCrossOrigin? webCrossOrigin) async {
    if (_disposed) {
      return;
    }
    if (!kIsWeb && !_isUnitTest()) {
      return;
    }

    await (await _platform).setWebCrossOrigin(
      SetWebCrossOriginRequest(
        crossOrigin: webCrossOrigin == null ? null : WebCrossOriginMessage.values[webCrossOrigin.index],
      ),
    );
    _webCrossOrigin = webCrossOrigin;
  }

  /// Sets a specific device output id on Web.
  Future<void> setWebSinkId(String webSinkId) async {
    if (_disposed) {
      return;
    }
    if (!kIsWeb && !_isUnitTest()) {
      return;
    }

    await (await _platform).setWebSinkId(SetWebSinkIdRequest(sinkId: webSinkId));
    _webSinkId = webSinkId;
  }

  /// Releases all resources associated with this player. You must invoke this
  /// after you are done with the player.
  Future<void> dispose() => _lock.synchronized(() async {
    if (_disposed) {
      return;
    }
    await stop();
    _disposed = true;
    if (_nativePlatform != null) {
      await _disposePlatform(await _nativePlatform!);
      _nativePlatform = null;
    }
    if (_idlePlatform != null) {
      await _disposePlatform(_idlePlatform!);
      _idlePlatform = null;
    }
    _playlist.children.clear();
    for (final s in _audioSources.values) {
      s._dispose();
    }
    _audioSources.clear();
    unawaited(_proxy.stop());
    await _playerDataSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    await _androidAudioAttributesSubscription?.cancel();
    await _becomingNoisyEventSubscription?.cancel();
    await _interruptionEventSubscription?.cancel();
    await _positionDiscontinuitySubscription?.cancel();
    await _currentIndexSubscription?.cancel();
    await _errorsSubscription?.cancel();
    await _errorsResetSubscription?.cancel();

    await _playerEventSubject.close();

    await _playbackEventPipe;

    await _playbackEventSubject.close();
    await _sequenceStateSubject.close();
    await _playingSubject.close();
    await _volumeSubject.close();
    await _speedSubject.close();
    await _pitchSubject.close();

    await _durationSubject.close();
    await _processingStateSubject.close();
    await _bufferedPositionSubject.close();
    await _icyMetadataSubject.close();
    await _androidAudioSessionIdSubject.close();
    await _errorSubject.close();
    await _playerStateSubject.close();
    await _skipSilenceEnabledSubject.close();
    await _positionDiscontinuitySubject.close();
    await _sequenceSubject.close();
    await _shuffleIndicesSubject.close();
    await _currentIndexSubject.close();
    await _loopModeSubject.close();
    await _shuffleModeEnabledSubject.close();
    await _shuffleModeEnabledSubject.close();
  });

  /// Switches to using the native platform when [active] is `true` and using the
  /// idle platform when [active] is `false`. If an audio source has been set,
  /// the returned future completes with its duration if known, or `null`
  /// otherwise.
  ///
  /// The platform will not switch if [active] == [_active] unless [force] is
  /// `true`.
  Future<Duration?>? _setPlatformActive(bool active, {Completer<void>? playCompleter, bool force = false}) {
    if (_disposed) {
      return null;
    }
    if (!force && (active == _active)) {
      return _loadFuture;
    }
    _platformLoading = active;

    // Warning! Tricky async code lies ahead.
    // (This should definitely be made less tricky)
    // This method itself is not asynchronous, and guarantees that _platform
    // will be set in this cycle to a Future. The platform returned by that
    // future takes time to initialise and so we need to handle the case where
    // that initialisation was interrupted by another call to
    // _setPlatformActive.

    // Store the current activation sequence number. activationNumber should
    // equal _activationCount for the duration of this call, unless it is
    // interrupted by another simultaneous call.
    final pluginLoadRequest = _pluginLoadRequest;
    final activationNumber = ++_activationCount;

    /// Tells whether we've been interrupted.
    bool wasInterrupted() =>
        _activationCount != activationNumber || pluginLoadRequest != _pluginLoadRequest || _disposed;

    final durationCompleter = Completer<Duration?>();

    // Checks if we were interrupted and aborts the current activation. If we
    // are interrupted, there are two cases:
    // 1. If we were activating the native platform, abort with an exception.
    // 2. If we were activating the idle dummy, abort silently.
    //
    // We should call this after each awaited call since those are opportunities
    // for other coroutines to run and interrupt this one.
    bool checkInterruption() {
      // No interruption.
      if (!wasInterrupted()) {
        return false;
      }
      pluginLoadRequest?.checkInterruption();
      // An interruption that we can ignore
      if (!active) {
        return true;
      }
      // An interruption that should throw
      throw PlayerInterruptedException('Loading interrupted');
    }

    // This method updates _active and _platform before yielding to the next
    // task in the event loop.
    _active = active;
    final position = this.position;
    final currentIndex = this.currentIndex;
    final playlist = _playlist;

    void subscribeToEvents(AudioPlayerInstancePlatform platform) {
      _playerDataSubscription = platform.playerDataMessageStream.listen(
        (message) {
          if (message.playing != null && message.playing != playing) {
            _playerEventSubject.add(playerEvent.copyWith(playing: message.playing));
          }
          if (message.volume != null) {
            _volumeSubject.add(message.volume!);
          }
          if (message.speed != null) {
            _speedSubject.add(message.speed!);
          }
          if (message.pitch != null) {
            _pitchSubject.add(message.pitch!);
          }
          if (message.loopMode != null) {
            _sequenceStateSubject.add(sequenceState.copyWith(loopMode: LoopMode.values[message.loopMode!.index]));
          }
          if (message.shuffleMode != null) {
            _sequenceStateSubject.add(
              sequenceState.copyWith(shuffleModeEnabled: message.shuffleMode != ShuffleModeMessage.none),
            );
          }
        },
        onDone: () {
          _playerDataSubscription = null;
        },
      );
      _playbackEventSubscription = platform.playbackEventMessageStream.listen((message) {
        var duration = message.duration;
        final index = message.currentIndex ?? currentIndex;
        if (index != null && index < sequence.length) {
          if (duration == null) {
            duration = sequence[index].duration;
          } else {
            sequence[index].duration = duration;
          }
        }
        if (_platformLoading && message.processingState != ProcessingStateMessage.idle) {
          _platformLoading = false;
        }
        final newPlaybackEvent = PlaybackEvent(
          // The platform may emit an idle state while it's starting up which we
          // override here.
          processingState: _platformLoading
              ? ProcessingState.loading
              : ProcessingState.values[message.processingState.index],
          updateTime: message.updateTime,
          updatePosition: message.updatePosition,
          bufferedPosition: message.bufferedPosition,
          duration: duration,
          icyMetadata: message.icyMetadata == null ? null : IcyMetadata._fromMessage(message.icyMetadata!),
          currentIndex: index,
          androidAudioSessionId: message.androidAudioSessionId,
          errorCode: message.errorCode,
          errorMessage: message.errorMessage,
        );
        _loadFuture = Future.value(newPlaybackEvent.duration);
        if (newPlaybackEvent == playbackEvent) {
          return;
        }
        final oldPlaybackEvent = playbackEvent;
        _playerEventSubject.add(playerEvent.copyWith(playbackEvent: newPlaybackEvent));
        if (playbackEvent.processingState != oldPlaybackEvent.processingState &&
            playbackEvent.processingState == ProcessingState.idle &&
            _active) {
          unawaited(_setPlatformActive(false)?.catchError((_) => null));
        }
      }, onError: (Object e, [StackTrace? st]) {});
    }

    Future<AudioPlayerInstancePlatform> setPlatform() async {
      // We need to cancel before calling _disposePlatform in order to prevent a
      // MissingPluginException. This also means there will potentially be
      // unconsumed events which will unfortunately appear when spinning up a
      // new platform player. For now, we change the player ID to avoid wires
      // getting crossed, although it would be better to find a way to flush the
      // event channel and keep the same ID.

      AudioPlayerInstancePlatform inactiveResult(AudioPlayerInstancePlatform platform) {
        durationCompleter.complete(null);
        return platform;
      }

      final platform = await _lock.synchronized(() async {
        final oldPlatform = _platformValue;
        // Strangely, this throws "Cannot complete a future with itself" when
        // _playbackEventSubscription==null under flutter test.
        // await _playbackEventSubscription?.cancel();
        // await _playerDataSubscription?.cancel();
        if (_playbackEventSubscription != null) {
          await _playbackEventSubscription!.cancel();
        }
        if (_playerDataSubscription != null) {
          await _playerDataSubscription!.cancel();
        }

        if (!force) {
          if (oldPlatform != null && oldPlatform is! _IdleAudioPlayer) {
            await _disposePlatform(oldPlatform);
          }
        }
        // During initialisation, we must only use this platform reference in case
        // _platform is updated again during initialisation.
        final platform = active && !_disposed
            ? await (_nativePlatform = _pluginPlatform.init(
                InitRequest(
                  id: _id = _generateId(),
                  audioLoadConfiguration: _audioLoadConfiguration?._toMessage(),
                  androidAudioEffects: (_isAndroid() || _isUnitTest())
                      ? _audioPipeline.androidAudioEffects.map((audioEffect) => audioEffect._toMessage()).toList()
                      : [],
                  darwinAudioEffects: (_isDarwin() || _isUnitTest())
                      ? _audioPipeline.darwinAudioEffects.map((audioEffect) => audioEffect._toMessage()).toList()
                      : [],
                  androidAudioOffloadPreferences: _androidAudioOffloadPreferences?._toMessage(),
                  useLazyPreparation: _playlist.useLazyPreparation,
                ),
              ))
            : (_idlePlatform = _IdleAudioPlayer(
                id: _id = _generateId(),
                sequenceStream: sequenceStream,
                errorCode: playbackEvent.errorCode,
                errorMessage: playbackEvent.errorMessage,
              ));

        _platformValue = platform;
        return platform;
      });
      if (checkInterruption() || _disposed) {
        return inactiveResult(platform);
      }

      if (active) {
        if (playlist.children.isNotEmpty) {
          _playerEventSubject.add(
            playerEvent.copyWith(
              playbackEvent: playbackEvent.copyWith(updatePosition: position, processingState: ProcessingState.loading),
            ),
          );
        }

        final automaticallyWaitsToMinimizeStalling = this.automaticallyWaitsToMinimizeStalling;
        final playing = this.playing;
        // To avoid a glitch in ExoPlayer, ensure that any requested audio
        // attributes are set before loading the audio source.
        if (_isAndroid() || _isUnitTest()) {
          if (_androidApplyAudioAttributes) {
            final audioSession = await AudioSession.instance;
            if (checkInterruption()) {
              return inactiveResult(platform);
            }
            _androidAudioAttributes ??= audioSession.configuration?.androidAudioAttributes;
          }
          if (_androidAudioAttributes != null) {
            await _internalSetAndroidAudioAttributes(platform, _androidAudioAttributes!);
            if (checkInterruption()) {
              return inactiveResult(platform);
            }
          }
        }
        if (!automaticallyWaitsToMinimizeStalling) {
          // Only set if different from default.
          await platform.setAutomaticallyWaitsToMinimizeStalling(
            SetAutomaticallyWaitsToMinimizeStallingRequest(enabled: automaticallyWaitsToMinimizeStalling),
          );
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        // The platform player starts out with the default settings, so only
        // the settings that differ from them need a round trip.
        if (volume != 1) {
          await platform.setVolume(SetVolumeRequest(volume: volume));
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        if (speed != 1) {
          await platform.setSpeed(SetSpeedRequest(speed: speed));
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        if (pitch != 1) {
          try {
            await platform.setPitch(SetPitchRequest(pitch: pitch));
          } catch (e) {
            // setPitch not supported on this platform.
          }
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        if (skipSilenceEnabled) {
          try {
            await platform.setSkipSilence(SetSkipSilenceRequest(enabled: skipSilenceEnabled));
          } catch (e) {
            // setSkipSilence not supported on this platform.
          }
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        if (loopMode != LoopMode.off) {
          await platform.setLoopMode(SetLoopModeRequest(loopMode: LoopModeMessage.values[loopMode.index]));
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        if (shuffleModeEnabled) {
          await platform.setShuffleMode(SetShuffleModeRequest(shuffleMode: ShuffleModeMessage.all));
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        if (kIsWeb) {
          if (_webCrossOrigin != null) {
            await platform.setWebCrossOrigin(
              SetWebCrossOriginRequest(crossOrigin: WebCrossOriginMessage.values[_webCrossOrigin!.index]),
            );
            if (checkInterruption()) {
              return inactiveResult(platform);
            }
          }
          if (_webSinkId != '') {
            await platform.setWebSinkId(SetWebSinkIdRequest(sinkId: _webSinkId));
            if (checkInterruption()) {
              return inactiveResult(platform);
            }
          }
        }
        for (final audioEffect in _audioPipeline._audioEffects) {
          await audioEffect._activate(platform);
          if (checkInterruption()) {
            return inactiveResult(platform);
          }
        }
        if (playing) {
          unawaited(_sendPlayRequest(platform, playCompleter));
        }
      }

      subscribeToEvents(platform);

      try {
        final initialSeekValues = pluginLoadRequest?.initialSeekValues ?? (index: currentIndex, position: position);
        final duration = await _load(platform, _playlist, initialSeekValues: initialSeekValues);
        durationCompleter.complete(duration);
      } catch (e, stackTrace) {
        durationCompleter.completeError(e, stackTrace);
      }

      return platform;
    }

    _platform = setPlatform();
    return _platform.then((_) => durationCompleter.future);
  }

  /// Disposes of the given platform.
  Future<void> _disposePlatform(AudioPlayerInstancePlatform platform) async {
    if (platform is _IdleAudioPlayer) {
      await platform.dispose(DisposeRequest());
    } else {
      _nativePlatform = null;
      try {
        await _pluginPlatform.disposePlayer(DisposePlayerRequest(id: _id!));
      } catch (e) {
        // Fallback if disposePlayer hasn't been implemented.
        await platform.dispose(DisposeRequest());
      } finally {
        _id = null;
      }
    }
  }

  /// Clears the plugin's internal asset cache directory. Call this when the
  /// app's assets have changed to force assets to be re-fetched from the asset
  /// bundle.
  static Future<void> clearAssetCache() async {
    if (kIsWeb) {
      return;
    }
    await for (final file in (await _getCacheDir()).list()) {
      await file.delete(recursive: true);
    }
  }

  Exception _convertException(PlatformException e) {
    const kUnknownErrorCode = 9999999;
    const kInterruptedErrorCode = 10000000;
    final details = (e.details as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
    final index = details?['index'] as int? ?? currentIndex;
    final code = int.tryParse(e.code);
    if (code == null) {
      if (e.code == 'abort') {
        return PlayerInterruptedException(e.message);
      } else {
        return PlayerException(kUnknownErrorCode, e.message, index);
      }
    } else if (code == kInterruptedErrorCode) {
      return PlayerInterruptedException(e.message);
    } else {
      return PlayerException(code, e.message, index);
    }
  }
}
