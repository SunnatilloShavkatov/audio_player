package uz.shs.audio_player;

import android.content.Context;
import android.media.audiofx.AudioEffect;
import android.media.audiofx.Equalizer;
import android.media.audiofx.LoudnessEnhancer;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Metadata;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.Timeline;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.Tracks;
import androidx.media3.common.util.Util;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlaybackException;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.LivePlaybackSpeedControl;
import androidx.media3.exoplayer.LoadControl;
import androidx.media3.exoplayer.dash.DashMediaSource;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import androidx.media3.exoplayer.metadata.MetadataOutput;
import androidx.media3.exoplayer.source.ClippingMediaSource;
import androidx.media3.exoplayer.source.MediaSource;
import androidx.media3.exoplayer.source.ProgressiveMediaSource;
import androidx.media3.exoplayer.source.SilenceMediaSource;
import androidx.media3.extractor.DefaultExtractorsFactory;
import androidx.media3.extractor.metadata.icy.IcyHeaders;
import androidx.media3.extractor.metadata.icy.IcyInfo;

import io.flutter.Log;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

public class AudioPlayer implements MethodCallHandler, Player.Listener, MetadataOutput {

    static final String TAG = "AudioPlayer";

    private final Context context;
    private final MethodChannel methodChannel;
    private final BetterEventChannel eventChannel;
    private final BetterEventChannel dataEventChannel;

    private ProcessingState processingState;
    private long updatePosition;
    private long updateTime;
    private long bufferedPosition;
    private Long seekPos;
    private long initialPos;
    private Integer initialIndex;
    private Result prepareResult;
    private Result playResult;
    private Result seekResult;
    private final Map<String, MediaSource> mediaSources = new HashMap<>();
    private IcyInfo icyInfo;
    private IcyHeaders icyHeaders;
    private int errorCount;
    private AudioAttributes pendingAudioAttributes;
    private LoadControl loadControl;
    private final boolean offloadSchedulingEnabled;
    private LivePlaybackSpeedControl livePlaybackSpeedControl;
    private final List<Object> rawAudioEffects;
    private final List<AudioEffect> audioEffects = new ArrayList<>();
    private final Map<String, AudioEffect> audioEffectsMap = new HashMap<>();
    private int lastPlaylistLength = 0;
    private Map<String, Object> pendingPlaybackEvent;

    private ExoPlayer player;
    private Integer audioSessionId;
    private MediaSource mediaSource;
    private Integer currentIndex;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable bufferWatcher = new Runnable() {
        @Override
        public void run() {
            if (player == null) {
                return;
            }

            long newBufferedPosition = player.getBufferedPosition();
            if (newBufferedPosition != bufferedPosition) {
                // This method updates bufferedPosition.
                broadcastImmediatePlaybackEvent();
            }
            switch (player.getPlaybackState()) {
                case Player.STATE_BUFFERING:
                    handler.postDelayed(this, 200);
                    break;
                case Player.STATE_READY:
                    if (player.getPlayWhenReady()) {
                        handler.postDelayed(this, 500);
                    } else {
                        handler.postDelayed(this, 1000);
                    }
                    break;
                default:
                    // Stop watching buffer
            }
        }
    };

    public AudioPlayer(
            final Context applicationContext,
            final BinaryMessenger messenger,
            final String id,
            Map<?, ?> audioLoadConfiguration,
            List<Object> rawAudioEffects,
            Boolean offloadSchedulingEnabled
    ) {
        this.context = applicationContext;
        this.rawAudioEffects = rawAudioEffects;
        this.offloadSchedulingEnabled = offloadSchedulingEnabled != null ? offloadSchedulingEnabled : false;
        methodChannel = new MethodChannel(messenger, "com.ryanheise.just_audio.methods." + id);
        methodChannel.setMethodCallHandler(this);
        eventChannel = new BetterEventChannel(messenger, "com.ryanheise.just_audio.events." + id);
        dataEventChannel = new BetterEventChannel(messenger, "com.ryanheise.just_audio.data." + id);
        processingState = ProcessingState.none;
        if (audioLoadConfiguration != null) {
            Map<?, ?> loadControlMap = (Map<?, ?>) audioLoadConfiguration.get("androidLoadControl");
            if (loadControlMap != null) {
                DefaultLoadControl.Builder builder = new DefaultLoadControl.Builder()
                        .setBufferDurationsMs(
                                (int) ((getLong(loadControlMap.get("minBufferDuration"))) / 1000),
                                (int) ((getLong(loadControlMap.get("maxBufferDuration"))) / 1000),
                                (int) ((getLong(loadControlMap.get("bufferForPlaybackDuration"))) / 1000),
                                (int) ((getLong(loadControlMap.get("bufferForPlaybackAfterRebufferDuration"))) / 1000)
                        )
                        .setPrioritizeTimeOverSizeThresholds((Boolean) loadControlMap.get("prioritizeTimeOverSizeThresholds"))
                        .setBackBuffer((int) ((getLong(loadControlMap.get("backBufferDuration"))) / 1000), false);
                if (loadControlMap.get("targetBufferBytes") != null) {
                    builder.setTargetBufferBytes((Integer) loadControlMap.get("targetBufferBytes"));
                }
                loadControl = builder.build();
            }
            Map<?, ?> livePlaybackSpeedControlMap = (Map<?, ?>) audioLoadConfiguration.get("androidLivePlaybackSpeedControl");
            if (livePlaybackSpeedControlMap != null) {
                DefaultLivePlaybackSpeedControl.Builder builder = new DefaultLivePlaybackSpeedControl.Builder()
                        .setFallbackMinPlaybackSpeed((float) ((double) ((Double) livePlaybackSpeedControlMap.get("fallbackMinPlaybackSpeed"))))
                        .setFallbackMaxPlaybackSpeed((float) ((double) ((Double) livePlaybackSpeedControlMap.get("fallbackMaxPlaybackSpeed"))))
                        .setMinUpdateIntervalMs(((getLong(livePlaybackSpeedControlMap.get("minUpdateInterval"))) / 1000))
                        .setProportionalControlFactor((float) ((double) ((Double) livePlaybackSpeedControlMap.get("proportionalControlFactor"))))
                        .setMaxLiveOffsetErrorMsForUnitSpeed(((getLong(livePlaybackSpeedControlMap.get("maxLiveOffsetErrorForUnitSpeed"))) / 1000))
                        .setTargetLiveOffsetIncrementOnRebufferMs(((getLong(livePlaybackSpeedControlMap.get("targetLiveOffsetIncrementOnRebuffer"))) / 1000))
                        .setMinPossibleLiveOffsetSmoothingFactor((float) ((double) ((Double) livePlaybackSpeedControlMap.get("minPossibleLiveOffsetSmoothingFactor"))));
                livePlaybackSpeedControl = builder.build();
            }
        }
    }

    private void startWatchingBuffer() {
        handler.removeCallbacks(bufferWatcher);
        handler.post(bufferWatcher);
    }

    private void setAudioSessionId(int audioSessionId) {
        if (audioSessionId == C.AUDIO_SESSION_ID_UNSET) {
            this.audioSessionId = null;
        } else {
            this.audioSessionId = audioSessionId;
        }
        clearAudioEffects();
        if (this.audioSessionId != null) {
            for (Object rawAudioEffect : rawAudioEffects) {
                Map<?, ?> json = (Map<?, ?>) rawAudioEffect;
                AudioEffect audioEffect = decodeAudioEffect(rawAudioEffect, this.audioSessionId);
                if ((Boolean) json.get("enabled")) {
                    audioEffect.setEnabled(true);
                }
                audioEffects.add(audioEffect);
                audioEffectsMap.put((String) json.get("type"), audioEffect);
            }
        }
        enqueuePlaybackEvent();
    }

    @Override
    public void onAudioSessionIdChanged(int audioSessionId) {
        setAudioSessionId(audioSessionId);
        broadcastPendingPlaybackEvent();
    }

    @Override
    public void onMetadata(Metadata metadata) {
        for (int i = 0; i < metadata.length(); i++) {
            final Metadata.Entry entry = metadata.get(i);
            if (entry instanceof IcyInfo) {
                icyInfo = (IcyInfo) entry;
                broadcastImmediatePlaybackEvent();
            }
        }
    }

    @Override
    public void onTracksChanged(Tracks tracks) {
        for (int i = 0; i < tracks.getGroups().size(); i++) {
            TrackGroup trackGroup = tracks.getGroups().get(i).getMediaTrackGroup();

            for (int j = 0; j < trackGroup.length; j++) {
                Metadata metadata = trackGroup.getFormat(j).metadata;

                if (metadata != null) {
                    for (int k = 0; k < metadata.length(); k++) {
                        final Metadata.Entry entry = metadata.get(k);
                        if (entry instanceof IcyHeaders) {
                            icyHeaders = (IcyHeaders) entry;
                            broadcastImmediatePlaybackEvent();
                        }
                    }
                }
            }
        }
    }

    private void updatePositionIfChanged() {
        if (getCurrentPosition() == updatePosition) return;
        updatePosition = getCurrentPosition();
        updateTime = System.currentTimeMillis();
    }

    private void updatePosition() {
        updatePosition = getCurrentPosition();
        updateTime = System.currentTimeMillis();
    }

    @Override
    public void onPositionDiscontinuity(@NonNull Player.PositionInfo oldPosition, @NonNull Player.PositionInfo newPosition, int reason) {
        updatePosition();
        switch (reason) {
            case Player.DISCONTINUITY_REASON_AUTO_TRANSITION:
            case Player.DISCONTINUITY_REASON_SEEK:
                updateCurrentIndex();
                break;
        }
        broadcastImmediatePlaybackEvent();
    }

    @Override
    public void onTimelineChanged(@NonNull Timeline timeline, int reason) {
        if (initialPos != C.TIME_UNSET || initialIndex != null) {
            int windowIndex = initialIndex != null ? initialIndex : 0;
            player.seekTo(windowIndex, initialPos);
            initialIndex = null;
            initialPos = C.TIME_UNSET;
        }
        if (updateCurrentIndex()) {
            broadcastImmediatePlaybackEvent();
        }
        if (player.getPlaybackState() == Player.STATE_ENDED) {
            try {
                if (player.getPlayWhenReady()) {
                    if (lastPlaylistLength == 0 && player.getMediaItemCount() > 0) {
                        player.seekTo(0, 0L);
                    } else if (player.hasNextMediaItem()) {
                        player.seekToNextMediaItem();
                    }
                } else {
                    if (player.getCurrentMediaItemIndex() < player.getMediaItemCount()) {
                        player.seekTo(player.getCurrentMediaItemIndex(), 0L);
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        lastPlaylistLength = player.getMediaItemCount();
    }

    private boolean updateCurrentIndex() {
        Integer newIndex = player.getCurrentMediaItemIndex();
        // newIndex is never null.
        // currentIndex is sometimes null.
        if (!newIndex.equals(currentIndex)) {
            currentIndex = newIndex;
            return true;
        }
        return false;
    }

    @Override
    public void onPlaybackStateChanged(int playbackState) {
        switch (playbackState) {
            case Player.STATE_READY:
                if (player.getPlayWhenReady())
                    updatePosition();
                processingState = ProcessingState.ready;
                broadcastImmediatePlaybackEvent();
                if (prepareResult != null) {
                    Map<String, Object> response = new HashMap<>();
                    response.put("duration", getDuration() == C.TIME_UNSET ? null : (1000 * getDuration()));
                    prepareResult.success(response);
                    prepareResult = null;
                    if (pendingAudioAttributes != null) {
                        player.setAudioAttributes(pendingAudioAttributes, false);
                        pendingAudioAttributes = null;
                    }
                }
                if (seekResult != null) {
                    completeSeek();
                }
                break;
            case Player.STATE_BUFFERING:
                updatePositionIfChanged();
                if (processingState != ProcessingState.buffering && processingState != ProcessingState.loading) {
                    processingState = ProcessingState.buffering;
                    broadcastImmediatePlaybackEvent();
                }
                startWatchingBuffer();
                break;
            case Player.STATE_ENDED:
                if (processingState != ProcessingState.completed) {
                    updatePosition();
                    processingState = ProcessingState.completed;
                    broadcastImmediatePlaybackEvent();
                }
                if (prepareResult != null) {
                    Map<String, Object> response = new HashMap<>();
                    prepareResult.success(response);
                    prepareResult = null;
                    if (pendingAudioAttributes != null) {
                        player.setAudioAttributes(pendingAudioAttributes, false);
                        pendingAudioAttributes = null;
                    }
                }
                if (playResult != null) {
                    playResult.success(new HashMap<String, Object>());
                    playResult = null;
                }
                break;
        }
    }

    @Override
    public void onPlayerError(@NonNull PlaybackException error) {
        if (error instanceof ExoPlaybackException) {
            final ExoPlaybackException exoError = (ExoPlaybackException) error;
            switch (exoError.type) {
                case ExoPlaybackException.TYPE_SOURCE:
                    Log.e(TAG, "TYPE_SOURCE: " + exoError.getSourceException().getMessage());
                    break;

                case ExoPlaybackException.TYPE_RENDERER:
                    Log.e(TAG, "TYPE_RENDERER: " + exoError.getRendererException().getMessage());
                    break;

                case ExoPlaybackException.TYPE_UNEXPECTED:
                    Log.e(TAG, "TYPE_UNEXPECTED: " + exoError.getUnexpectedException().getMessage());
                    break;

                default:
                    Log.e(TAG, "default ExoPlaybackException: " + exoError.getUnexpectedException().getMessage());
            }
            // TODO: send both errorCode and type
            sendError(String.valueOf(exoError.type), exoError.getMessage(), mapOf("index", currentIndex));
        } else {
            Log.e(TAG, "default PlaybackException: " + error.getMessage());
            sendError(String.valueOf(error.errorCode), error.getMessage(), mapOf("index", currentIndex));
        }
        errorCount++;
        if (player.hasNextMediaItem() && currentIndex != null && errorCount <= 5) {
            int nextIndex = currentIndex + 1;
            Timeline timeline = player.getCurrentTimeline();
            // This condition is due to: https://github.com/ryanheise/just_audio/pull/310
            if (nextIndex < timeline.getWindowCount()) {
                // TODO: pass in initial position here.
                player.setMediaSource(mediaSource);
                player.prepare();
                player.seekTo(nextIndex, 0);
            }
        }
    }

    private void completeSeek() {
        seekPos = null;
        seekResult.success(new HashMap<String, Object>());
        seekResult = null;
    }

    @Override
    public void onMethodCall(@NonNull final MethodCall call, @NonNull final Result result) {
        ensurePlayerInitialized();

        try {
            switch (call.method) {
                case "load":
                    Long initialPosition = getLong(call.argument("initialPosition"));
                    Integer initialIndex = call.argument("initialIndex");
                    load(getAudioSource(call.argument("audioSource")),
                            initialPosition == null ? C.TIME_UNSET : initialPosition / 1000,
                            initialIndex, result);
                    break;
                case "play":
                    play(result);
                    break;
                case "pause":
                    pause();
                    result.success(new HashMap<String, Object>());
                    break;
                case "setVolume":
                    setVolume((float) ((double) ((Double) call.argument("volume"))));
                    result.success(new HashMap<String, Object>());
                    break;
                case "setSpeed":
                    setSpeed((float) ((double) ((Double) call.argument("speed"))));
                    result.success(new HashMap<String, Object>());
                    break;
                case "setPitch":
                    setPitch((float) ((double) ((Double) call.argument("pitch"))));
                    result.success(new HashMap<String, Object>());
                    break;
                case "setSkipSilence":
                    setSkipSilenceEnabled(call.argument("enabled"));
                    result.success(new HashMap<String, Object>());
                    break;
                case "setLoopMode":
                    setLoopMode(call.argument("loopMode"));
                    result.success(new HashMap<String, Object>());
                    break;
                case "setShuffleMode":
                    setShuffleModeEnabled((Integer) call.argument("shuffleMode") == 1);
                    result.success(new HashMap<String, Object>());
                    break;
                case "setShuffleOrder":
                    setShuffleOrder(call.argument("audioSource"));
                    result.success(new HashMap<String, Object>());
                    break;
                case "setAutomaticallyWaitsToMinimizeStalling":
                case "setCanUseNetworkResourcesForLiveStreamingWhilePaused":
                case "setPreferredPeakBitRate":
                    result.success(new HashMap<String, Object>());
                    break;
                case "seek":
                    Long position = getLong(call.argument("position"));
                    Integer index = call.argument("index");
                    seek(position == null ? C.TIME_UNSET : position / 1000, index, result);
                    break;
                case "concatenatingInsertAll":
//                concatenating(call.argument("id"))
//                        .addMediaSources(call.argument("index"), getAudioSources(call.argument("children")), handler, () -> result.success(new HashMap<String, Object>()));
//                concatenating(call.argument("id"))
//                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                    break;
                case "concatenatingRemoveRange":
//                concatenating(call.argument("id"))
//                        .removeMediaSourceRange(call.argument("startIndex"), call.argument("endIndex"), handler, () -> result.success(new HashMap<String, Object>()));
//                concatenating(call.argument("id"))
//                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                    break;
                case "concatenatingMove":
//                concatenating(call.argument("id"))
//                        .moveMediaSource(call.argument("currentIndex"), call.argument("newIndex"), handler, () -> result.success(new HashMap<String, Object>()));
//                concatenating(call.argument("id"))
//                        .setShuffleOrder(decodeShuffleOrder(call.argument("shuffleOrder")));
                    break;
                case "setAndroidAudioAttributes":
                    setAudioAttributes(call.argument("contentType"), call.argument("flags"), call.argument("usage"));
                    result.success(new HashMap<String, Object>());
                    break;
                case "audioEffectSetEnabled":
                    audioEffectSetEnabled(call.argument("type"), call.argument("enabled"));
                    result.success(new HashMap<String, Object>());
                    break;
                case "androidLoudnessEnhancerSetTargetGain":
                    loudnessEnhancerSetTargetGain(call.argument("targetGain"));
                    result.success(new HashMap<String, Object>());
                    break;
                case "androidEqualizerGetParameters":
                    result.success(equalizerAudioEffectGetParameters());
                    break;
                case "androidEqualizerBandSetGain":
                    equalizerBandSetGain(call.argument("bandIndex"), call.argument("gain"));
                    result.success(new HashMap<String, Object>());
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (IllegalStateException e) {
            e.printStackTrace();
            result.error("Illegal state: " + e.getMessage(), null, null);
        } catch (Exception e) {
            e.printStackTrace();
            result.error("Error: " + e, null, null);
        } finally {
            broadcastPendingPlaybackEvent();
        }
    }

    private void setShuffleOrder(final Object json) {
        Map<?, ?> map = (Map<?, ?>) json;
        String id = mapGet(map, "id");
        MediaSource mediaSource = mediaSources.get(id);
        if (mediaSource == null) return;
        switch ((String) mapGet(map, "type")) {
            case "concatenating":
                List<Object> children = mapGet(map, "children");
                for (Object child : children) {
                    setShuffleOrder(child);
                }
                break;
            case "looping":
                setShuffleOrder(mapGet(map, "child"));
                break;
        }
    }

    private MediaSource getAudioSource(final Object json) {
        Map<?, ?> map = (Map<?, ?>) json;
        String id = (String) map.get("id");
        MediaSource mediaSource = mediaSources.get(id);
        if (mediaSource == null) {
            mediaSource = decodeAudioSource(map);
            mediaSources.put(id, mediaSource);
        }
        return mediaSource;
    }

    private DefaultExtractorsFactory buildExtractorsFactory(Map<?, ?> options) {
        DefaultExtractorsFactory extractorsFactory = new DefaultExtractorsFactory();
        boolean constantBitrateSeekingEnabled = true;
        boolean constantBitrateSeekingAlwaysEnabled = false;
        int mp3Flags = 0;
        if (options != null) {
            Map<?, ?> androidExtractorOptions = (Map<?, ?>) options.get("androidExtractorOptions");
            if (androidExtractorOptions != null) {
                constantBitrateSeekingEnabled = (Boolean) androidExtractorOptions.get("constantBitrateSeekingEnabled");
                constantBitrateSeekingAlwaysEnabled = (Boolean) androidExtractorOptions.get("constantBitrateSeekingAlwaysEnabled");
                mp3Flags = (Integer) androidExtractorOptions.get("mp3Flags");
            }
        }
        extractorsFactory.setConstantBitrateSeekingEnabled(constantBitrateSeekingEnabled);
        extractorsFactory.setConstantBitrateSeekingAlwaysEnabled(constantBitrateSeekingAlwaysEnabled);
        extractorsFactory.setMp3ExtractorFlags(mp3Flags);
        return extractorsFactory;
    }

    private MediaSource decodeAudioSource(final Object json) {
        Map<?, ?> map = (Map<?, ?>) json;
        String id = (String) map.get("id");
        switch ((String) map.get("type")) {
            case "progressive":
                return new ProgressiveMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")), buildExtractorsFactory(mapGet(map, "options")))
                        .createMediaSource(new MediaItem.Builder()
                                .setUri(Uri.parse((String) map.get("uri")))
                                .setTag(id)
                                .build());
            case "dash":
                return new DashMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                        .createMediaSource(new MediaItem.Builder()
                                .setUri(Uri.parse((String) map.get("uri")))
                                .setMimeType(MimeTypes.APPLICATION_MPD)
                                .setTag(id)
                                .build());
            case "hls":
                return new HlsMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                        .createMediaSource(new MediaItem.Builder()
                                .setUri(Uri.parse((String) map.get("uri")))
                                .setMimeType(MimeTypes.APPLICATION_M3U8)
                                .build());
            case "silence":
                return new SilenceMediaSource.Factory()
                        .setDurationUs(getLong(map.get("duration")))
                        .setTag(id)
                        .createMediaSource();
            case "concatenating":
//            MediaSource[] mediaSources = getAudioSourcesArray(map.get("children"));
//            return new ConcatenatingMediaSource(
//                    false, // isAtomic
//                    (Boolean)map.get("useLazyPreparation"),
//                    decodeShuffleOrder(mapGet(map, "shuffleOrder")),
//                    mediaSources);
            case "clipping":
                Long start = getLong(map.get("start"));
                Long end = getLong(map.get("end"));
                return new ClippingMediaSource(getAudioSource(map.get("child")),
                        start != null ? start : 0,
                        end != null ? end : C.TIME_END_OF_SOURCE);
            case "looping":
//            Integer count = (Integer)map.get("count");
//            MediaSource looperChild = getAudioSource(map.get("child"));
//            MediaSource[] looperChildren = new MediaSource[count];
//            for (int i = 0; i < looperChildren.length; i++) {
//                looperChildren[i] = looperChild;
//            }
//            return new ConcatenatingMediaSource(looperChildren);
            default:
                throw new IllegalArgumentException("Unknown AudioSource type: " + map.get("type"));
        }
    }

    private List<MediaSource> getAudioSources(final Object json) {
        if (!(json instanceof List)) throw new RuntimeException("List expected: " + json);
        List<?> audioSources = (List<?>) json;
        List<MediaSource> mediaSources = new ArrayList<MediaSource>();
        for (int i = 0; i < audioSources.size(); i++) {
            mediaSources.add(getAudioSource(audioSources.get(i)));
        }
        return mediaSources;
    }

    private AudioEffect decodeAudioEffect(final Object json, int audioSessionId) {
        Map<?, ?> map = (Map<?, ?>) json;
        String type = (String) map.get("type");
        switch (type) {
            case "AndroidLoudnessEnhancer":
                if (Build.VERSION.SDK_INT < 19)
                    throw new RuntimeException("AndroidLoudnessEnhancer requires minSdkVersion >= 19");
                int targetGain = (int) Math.round((((Double) map.get("targetGain")) * 1000.0));
                LoudnessEnhancer loudnessEnhancer = new LoudnessEnhancer(audioSessionId);
                loudnessEnhancer.setTargetGain(targetGain);
                return loudnessEnhancer;
            case "AndroidEqualizer":
                return new Equalizer(0, audioSessionId);
            default:
                throw new IllegalArgumentException("Unknown AudioEffect type: " + map.get("type"));
        }
    }

    private void clearAudioEffects() {
        for (Iterator<AudioEffect> it = audioEffects.iterator(); it.hasNext(); ) {
            AudioEffect audioEffect = it.next();
            audioEffect.release();
            it.remove();
        }
        audioEffectsMap.clear();
    }

    private DataSource.Factory buildDataSourceFactory(Map<?, ?> headers) {
        final Map<String, String> stringHeaders = castToStringMap(headers);
        String userAgent = null;
        if (stringHeaders != null) {
            userAgent = stringHeaders.remove("User-Agent");
            if (userAgent == null) {
                userAgent = stringHeaders.remove("user-agent");
            }
        }
        if (userAgent == null) {
            userAgent = Util.getUserAgent(context, "just_audio");
        }
        DefaultHttpDataSource.Factory httpDataSourceFactory = new DefaultHttpDataSource.Factory()
                .setUserAgent(userAgent)
                .setAllowCrossProtocolRedirects(true);
        if (stringHeaders != null && stringHeaders.size() > 0) {
            httpDataSourceFactory.setDefaultRequestProperties(stringHeaders);
        }
        return new DefaultDataSource.Factory(context, httpDataSourceFactory);
    }

    private void load(final MediaSource mediaSource, final long initialPosition, final Integer initialIndex, final Result result) {
        this.initialPos = initialPosition;
        this.initialIndex = initialIndex;
        currentIndex = initialIndex != null ? initialIndex : 0;
        switch (processingState) {
            case none:
                break;
            case loading:
                abortExistingConnection();
                player.stop();
                break;
            default:
                player.stop();
                break;
        }
        errorCount = 0;
        prepareResult = result;
        updatePosition();
        processingState = ProcessingState.loading;
        enqueuePlaybackEvent();
        this.mediaSource = mediaSource;
        // TODO: pass in initial position here.
        player.setMediaSource(mediaSource);
        player.prepare();
    }

    private void ensurePlayerInitialized() {
        if (player == null) {
            ExoPlayer.Builder builder = new ExoPlayer.Builder(context);
            if (loadControl != null) {
                builder.setLoadControl(loadControl);
            }
            if (livePlaybackSpeedControl != null) {
                builder.setLivePlaybackSpeedControl(livePlaybackSpeedControl);
            }
            if (offloadSchedulingEnabled) {
//                builder.setRenderersFactory(new DefaultRenderersFactory(context).setEnableAudioOffload(true));
                builder.setRenderersFactory(new DefaultRenderersFactory(context).setEnableAudioFloatOutput(true));
            }
            player = builder.build();
//            player.experimentalSetOffloadSchedulingEnabled(offloadSchedulingEnabled);
//            player.experimentalSetOffloadSchedulingEnabled(offloadSchedulingEnabled);
            setAudioSessionId(player.getAudioSessionId());
            player.addListener(this);
        }
    }

    private void setAudioAttributes(int contentType, int flags, int usage) {
        AudioAttributes.Builder builder = new AudioAttributes.Builder();
        builder.setContentType(contentType);
        builder.setFlags(flags);
        builder.setUsage(usage);
        //builder.setAllowedCapturePolicy((Integer)json.get("allowedCapturePolicy"));
        AudioAttributes audioAttributes = builder.build();
        if (processingState == ProcessingState.loading) {
            // audio attributes should be set either before or after loading to
            // avoid an ExoPlayer glitch.
            pendingAudioAttributes = audioAttributes;
        } else {
            player.setAudioAttributes(audioAttributes, false);
        }
    }

    private void audioEffectSetEnabled(String type, boolean enabled) {
        audioEffectsMap.get(type).setEnabled(enabled);
    }

    private void loudnessEnhancerSetTargetGain(double targetGain) {
        int targetGainMillibels = (int) Math.round(targetGain * 1000.0);
        ((LoudnessEnhancer) audioEffectsMap.get("AndroidLoudnessEnhancer")).setTargetGain(targetGainMillibels);
    }

    private Map<String, Object> equalizerAudioEffectGetParameters() {
        Equalizer equalizer = (Equalizer) audioEffectsMap.get("AndroidEqualizer");
        ArrayList<Object> rawBands = new ArrayList<>();
        for (short i = 0; i < equalizer.getNumberOfBands(); i++) {
            rawBands.add(mapOf(
                    "index", i,
                    "lowerFrequency", (double) equalizer.getBandFreqRange(i)[0] / 1000.0,
                    "upperFrequency", (double) equalizer.getBandFreqRange(i)[1] / 1000.0,
                    "centerFrequency", (double) equalizer.getCenterFreq(i) / 1000.0,
                    "gain", equalizer.getBandLevel(i) / 1000.0
            ));
        }
        return mapOf(
                "parameters", mapOf(
                        "minDecibels", equalizer.getBandLevelRange()[0] / 1000.0,
                        "maxDecibels", equalizer.getBandLevelRange()[1] / 1000.0,
                        "bands", rawBands
                )
        );
    }

    private void equalizerBandSetGain(int bandIndex, double gain) {
        ((Equalizer) audioEffectsMap.get("AndroidEqualizer")).setBandLevel((short) bandIndex, (short) (Math.round(gain * 1000.0)));
    }

    /// Creates an event based on the current state.
    private Map<String, Object> createPlaybackEvent() {
        final Map<String, Object> event = new HashMap<String, Object>();
        Long duration = getDuration() == C.TIME_UNSET ? null : (1000 * getDuration());
        bufferedPosition = player != null ? player.getBufferedPosition() : 0L;
        event.put("processingState", processingState.ordinal());
        event.put("updatePosition", 1000 * updatePosition);
        event.put("updateTime", updateTime);
        event.put("bufferedPosition", 1000 * Math.max(updatePosition, bufferedPosition));
        event.put("icyMetadata", collectIcyMetadata());
        event.put("duration", duration);
        event.put("currentIndex", currentIndex);
        event.put("androidAudioSessionId", audioSessionId);
        return event;
    }

    // Broadcast the pending playback event if it was set.
    private void broadcastPendingPlaybackEvent() {
        if (pendingPlaybackEvent != null) {
            eventChannel.success(pendingPlaybackEvent);
            pendingPlaybackEvent = null;
        }
    }

    // Set a pending playback event that should be broadcast at
    // a later time. If we're in a Flutter method call, it will
    // be broadcast just before that method call returns. If
    // we're in an asynchronous callback, it is up to the caller
    // to eventually broadcast that event via
    // broadcastPendingPlaybackEvent.
    //
    // If this is called multiple times before
    // broadcastPendingPlaybackEvent, only the last event is
    // broadcast.
    private void enqueuePlaybackEvent() {
        final Map<String, Object> event = new HashMap<String, Object>();
        pendingPlaybackEvent = createPlaybackEvent();
    }

    // Broadcasts a new event immediately.
    private void broadcastImmediatePlaybackEvent() {
        enqueuePlaybackEvent();
        broadcastPendingPlaybackEvent();
    }

    private Map<String, Object> collectIcyMetadata() {
        final Map<String, Object> icyData = new HashMap<>();
        if (icyInfo != null) {
            final Map<String, String> info = new HashMap<>();
            info.put("title", icyInfo.title);
            info.put("url", icyInfo.url);
            icyData.put("info", info);
        }
        if (icyHeaders != null) {
            final Map<String, Object> headers = new HashMap<>();
            headers.put("bitrate", icyHeaders.bitrate);
            headers.put("genre", icyHeaders.genre);
            headers.put("name", icyHeaders.name);
            headers.put("metadataInterval", icyHeaders.metadataInterval);
            headers.put("url", icyHeaders.url);
            headers.put("isPublic", icyHeaders.isPublic);
            icyData.put("headers", headers);
        }
        return icyData;
    }

    private long getCurrentPosition() {
        if (initialPos != C.TIME_UNSET) {
            return initialPos;
        } else if (processingState == ProcessingState.none || processingState == ProcessingState.loading) {
            long pos = player.getCurrentPosition();
            if (pos < 0) pos = 0;
            return pos;
        } else if (seekPos != null && seekPos != C.TIME_UNSET) {
            return seekPos;
        } else {
            return player.getCurrentPosition();
        }
    }

    private long getDuration() {
        if (processingState == ProcessingState.none || processingState == ProcessingState.loading || player == null) {
            return C.TIME_UNSET;
        } else {
            return player.getDuration();
        }
    }

    private void sendError(String errorCode, String errorMsg) {
        sendError(errorCode, errorMsg, null);
    }

    private void sendError(String errorCode, String errorMsg, Object details) {
        if (prepareResult != null) {
            prepareResult.error(errorCode, errorMsg, details);
            prepareResult = null;
        }

        eventChannel.error(errorCode, errorMsg, details);
    }

    public void play(Result result) {
        if (player.getPlayWhenReady()) {
            result.success(new HashMap<String, Object>());
            return;
        }
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
        }
        playResult = result;
        player.setPlayWhenReady(true);
        updatePosition();
        if (processingState == ProcessingState.completed && playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
    }

    public void pause() {
        if (!player.getPlayWhenReady()) return;
        player.setPlayWhenReady(false);
        updatePosition();
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
    }

    public void setVolume(final float volume) {
        player.setVolume(volume);
    }

    public void setSpeed(final float speed) {
        PlaybackParameters params = player.getPlaybackParameters();
        if (params.speed == speed) return;
        player.setPlaybackParameters(new PlaybackParameters(speed, params.pitch));
        if (player.getPlayWhenReady())
            updatePosition();
        enqueuePlaybackEvent();
    }

    public void setPitch(final float pitch) {
        PlaybackParameters params = player.getPlaybackParameters();
        if (params.pitch == pitch) return;
        player.setPlaybackParameters(new PlaybackParameters(params.speed, pitch));
        enqueuePlaybackEvent();
    }

    public void setSkipSilenceEnabled(final boolean enabled) {
        player.setSkipSilenceEnabled(enabled);
    }

    public void setLoopMode(final int mode) {
        player.setRepeatMode(mode);
    }

    public void setShuffleModeEnabled(final boolean enabled) {
        player.setShuffleModeEnabled(enabled);
    }

    public void seek(final long position, final Integer index, final Result result) {
        if (processingState == ProcessingState.none || processingState == ProcessingState.loading) {
            result.success(new HashMap<String, Object>());
            return;
        }
        abortSeek();
        seekPos = position;
        seekResult = result;
        try {
            int windowIndex = index != null ? index : player.getCurrentMediaItemIndex();
            player.seekTo(windowIndex, position);
        } catch (RuntimeException e) {
            seekResult = null;
            seekPos = null;
            throw e;
        }
    }

    public void dispose() {
        if (processingState == ProcessingState.loading) {
            abortExistingConnection();
        }
        if (playResult != null) {
            playResult.success(new HashMap<String, Object>());
            playResult = null;
        }
        mediaSources.clear();
        mediaSource = null;
        clearAudioEffects();
        if (player != null) {
            player.release();
            player = null;
            processingState = ProcessingState.none;
            broadcastImmediatePlaybackEvent();
        }
        eventChannel.endOfStream();
        dataEventChannel.endOfStream();
    }

    private void abortSeek() {
        if (seekResult != null) {
            try {
                seekResult.success(new HashMap<String, Object>());
            } catch (RuntimeException e) {
                // Result already sent
            }
            seekResult = null;
            seekPos = null;
        }
    }

    private void abortExistingConnection() {
        sendError("abort", "Connection aborted");
    }

    // Dart can't distinguish between int sizes so
    // Flutter may send us a Long or an Integer
    // depending on the number of bits required to
    // represent it.
    public static Long getLong(Object o) {
        return (o == null || o instanceof Long) ? (Long) o : Long.valueOf((Integer) o);
    }

    @SuppressWarnings("unchecked")
    static <T> T mapGet(Object o, String key) {
        if (o instanceof Map) {
            return (T) ((Map<?, ?>) o).get(key);
        } else {
            return null;
        }
    }

    static Map<String, Object> mapOf(Object... args) {
        Map<String, Object> map = new HashMap<>();
        for (int i = 0; i < args.length; i += 2) {
            map.put((String) args[i], args[i + 1]);
        }
        return map;
    }

    static Map<String, String> castToStringMap(Map<?, ?> map) {
        if (map == null) return null;
        Map<String, String> map2 = new HashMap<>();
        for (Object key : map.keySet()) {
            map2.put((String) key, (String) map.get(key));
        }
        return map2;
    }

    enum ProcessingState {
        none,
        loading,
        buffering,
        ready,
        completed
    }
}
/// 1026