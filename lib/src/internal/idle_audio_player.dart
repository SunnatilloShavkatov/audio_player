part of '../audio_player.dart';

/// The stand-in platform implementation to use when the player is in the idle
/// state and the native platform is deallocated.
class _IdleAudioPlayer extends AudioPlayerInstancePlatform {
  new({
    required String id,
    required Stream<List<IndexedAudioSource>> sequenceStream,
    required this.errorCode,
    required this.errorMessage,
  }) : super(id) {
    _sequenceSubscription = sequenceStream.listen((sequence) => _sequence = sequence);
  }
  final _eventSubject = BehaviorSubject<PlaybackEventMessage>();
  Duration _position = Duration.zero;
  int? _index;
  List<IndexedAudioSource> _sequence = [];
  int? errorCode;
  String? errorMessage;
  StreamSubscription<List<IndexedAudioSource>>? _sequenceSubscription;

  /// Holds a pending request.
  SetAndroidAudioAttributesRequest? setAndroidAudioAttributesRequest;

  void _broadcastPlaybackEvent() {
    final updateTime = DateTime.now();
    _eventSubject.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.idle,
        updatePosition: _position,
        updateTime: updateTime,
        bufferedPosition: Duration.zero,
        icyMetadata: null,
        duration: _getDurationAtIndex(_index),
        currentIndex: _index,
        androidAudioSessionId: null,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
  }

  Duration? _getDurationAtIndex(int? index) =>
      index != null && index < _sequence.length ? _sequence[index].duration : null;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _eventSubject.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _index = request.initialIndex ?? 0;
    _position = request.initialPosition ?? Duration.zero;
    errorCode = null;
    errorMessage = null;
    _broadcastPlaybackEvent();
    return LoadResponse(duration: _getDurationAtIndex(_index));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();

  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async => SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async => SetShuffleOrderResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse> setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest request,
  ) async => SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();

  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(SetPreferredPeakBitRateRequest request) async =>
      SetPreferredPeakBitRateResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _position = request.position ?? Duration.zero;
    _index = request.index ?? _index;
    errorCode = null;
    errorMessage = null;
    _broadcastPlaybackEvent();
    return SeekResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) async {
    setAndroidAudioAttributesRequest = request;
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _sequenceSubscription?.cancel();
    return DisposeResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(ConcatenatingInsertAllRequest request) async {
    if (request.id == '') {
      if (_index == null) {
        if (request.children.isNotEmpty) {
          _index = 0;
          _broadcastPlaybackEvent();
        }
      } else {
        if (request.index <= _index!) {
          _index = _index! + request.children.length;
          _broadcastPlaybackEvent();
        }
      }
    }
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(ConcatenatingRemoveRangeRequest request) async {
    if (request.id == '' && _index != null) {
      if (request.startIndex <= _index!) {
        _index = min(request.shuffleOrder.length - 1, _index! - (min(_index!, request.endIndex) - request.startIndex));
        if (_index! < 0) {
          _index = null;
        }
        _broadcastPlaybackEvent();
      }
    }
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(ConcatenatingMoveRequest request) async {
    if (request.id == '' && _index != null && request.currentIndex != request.newIndex) {
      if (request.currentIndex == _index!) {
        _index = request.newIndex;
        _broadcastPlaybackEvent();
      } else if (request.currentIndex < _index! && request.newIndex >= _index!) {
        _index = _index! - 1;
        _broadcastPlaybackEvent();
      } else if (request.currentIndex > _index! && request.newIndex <= _index!) {
        _index = _index! + 1;
        _broadcastPlaybackEvent();
      }
    }
    return ConcatenatingMoveResponse();
  }

  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) async =>
      AudioEffectSetEnabledResponse();

  @override
  Future<AndroidLoudnessEnhancerSetTargetGainResponse> androidLoudnessEnhancerSetTargetGain(
    AndroidLoudnessEnhancerSetTargetGainRequest request,
  ) async => AndroidLoudnessEnhancerSetTargetGainResponse();

  @override
  Future<AndroidEqualizerBandSetGainResponse> androidEqualizerBandSetGain(
    AndroidEqualizerBandSetGainRequest request,
  ) async => AndroidEqualizerBandSetGainResponse();

  @override
  Future<AndroidEqualizerGetParametersResponse> androidEqualizerGetParameters(
    AndroidEqualizerGetParametersRequest request,
  ) async => AndroidEqualizerGetParametersResponse(
    parameters: AndroidEqualizerParametersMessage(minDecibels: 0, maxDecibels: 10, bands: []),
  );

  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(SetAllowsExternalPlaybackRequest request) async =>
      SetAllowsExternalPlaybackResponse();
}

/// Encapsulates the arguments passed to the current invocation of
/// `AudioSource.setAudioSources`.
class _PluginLoadRequest {
  new({
    required this.audioSources,
    this.preload = true,
    this.initialIndex,
    this.initialPosition,
    required this.shuffleOrder,
  });
  List<AudioSource> audioSources;
  bool preload;
  int? initialIndex;
  Duration? initialPosition;
  ShuffleOrder shuffleOrder;
  bool interrupted = false;

  _InitialSeekValues get initialSeekValues => (index: initialIndex, position: initialPosition);

  /// Makes a seek issued before the platform loads the playlist the place to
  /// start from.
  void seekInitialValues({int? index, Duration? position}) {
    initialIndex = index ?? initialIndex;
    initialPosition = position;
  }

  void checkInterruption() {
    if (!interrupted) {
      return;
    }
    throw PlayerInterruptedException('Loading interrupted');
  }
}

/// Holds the initial requested position and index for a newly loaded audio
/// source.
typedef _InitialSeekValues = ({int? index, Duration? position});
