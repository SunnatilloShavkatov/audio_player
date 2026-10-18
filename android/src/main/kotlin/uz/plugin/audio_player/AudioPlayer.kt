package uz.plugin.audio_player

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Metadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences
import androidx.media3.common.Tracks
import androidx.media3.common.util.Util
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LivePlaybackSpeedControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.NoSampleRenderer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.metadata.MetadataOutput
import androidx.media3.exoplayer.source.ClippingMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.ShuffleOrder
import androidx.media3.exoplayer.source.ShuffleOrder.DefaultShuffleOrder
import androidx.media3.exoplayer.source.SilenceMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.metadata.icy.IcyHeaders
import androidx.media3.extractor.metadata.icy.IcyInfo
import io.flutter.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.Random

class AudioPlayer(
    applicationContext: Context,
    messenger: BinaryMessenger,
    id: String,
    audioLoadConfiguration: Map<*, *>?,
    private val rawAudioEffects: List<Any?>,
    audioOffloadPreferences: Map<*, *>?,
    offloadSchedulingEnabled: Boolean?,
    private val useLazyPreparation: Boolean,
    private val handleInterruptions: Boolean,
) : MethodCallHandler, Player.Listener, MetadataOutput {

    private enum class ProcessingState {
        idle,
        loading,
        buffering,
        ready,
        completed,
    }

    private val context: Context = applicationContext
    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "uz.plugin.audio_player.methods.$id")
    private val eventChannel = BetterEventChannel(messenger, "uz.plugin.audio_player.events.$id")
    private val dataEventChannel = BetterEventChannel(messenger, "uz.plugin.audio_player.data.$id")

    private var processingState = ProcessingState.idle
    private var updatePosition = 0L
    private var updateTime = 0L
    private var bufferedPosition = 0L
    private var seekPos: Long? = null
    private var prepareResult: Result? = null
    private var playResult: Result? = null
    private var seekResult: Result? = null
    private val mediaSources = HashMap<String, MediaSource>()
    private var icyInfo: IcyInfo? = null
    private var icyHeaders: IcyHeaders? = null
    private var cachedIcyMetadata: Map<String, Any?>? = null
    private var pendingAudioAttributes: AudioAttributes? = null
    private var loadControl: LoadControl? = null
    private val audioOffloadPreferences: AudioOffloadPreferences
    private var livePlaybackSpeedControl: LivePlaybackSpeedControl? = null
    private val audioEffects = ArrayList<AudioEffect>()
    private val audioEffectsMap = HashMap<String, AudioEffect>()
    private var lastPlaylistLength = 0
    private var pendingPlaybackEvent: Map<String, Any?>? = null

    private var exoPlayer: ExoPlayer? = null
    private val player: ExoPlayer get() = exoPlayer!!
    private var audioSessionId: Int? = null
    private var errorCode: Int? = null
    private var errorMessage: String? = null
    private var currentIndex: Int? = null
    private val handler = Handler(Looper.getMainLooper())
    // ExoPlayer has no callback for buffered position changes, so it is polled,
    // but only while it can actually change: when the player is buffering or
    // loading. Once loading stops the watcher takes a final reading and quits,
    // and onIsLoadingChanged restarts it. This keeps an idle or fully buffered
    // player from waking the main thread every few hundred milliseconds.
    private val bufferWatcher = object : Runnable {
        override fun run() {
            val player = exoPlayer ?: return

            val newBufferedPosition = player.bufferedPosition
            if (newBufferedPosition != bufferedPosition) {
                // This method updates bufferedPosition.
                broadcastImmediatePlaybackEvent()
            }
            when {
                player.playbackState == Player.STATE_BUFFERING -> handler.postDelayed(this, 200)
                player.playbackState == Player.STATE_READY && player.isLoading ->
                    handler.postDelayed(this, if (player.playWhenReady) 500 else 1000)
                else -> {
                    // Stop watching buffer
                }
            }
        }
    }

    init {
        val offloadEnabled = offloadSchedulingEnabled ?: false
        if (audioOffloadPreferences != null) {
            this.audioOffloadPreferences = AudioOffloadPreferences.Builder()
                .setIsGaplessSupportRequired(audioOffloadPreferences["isGaplessSupportRequired"] as Boolean)
                .setIsSpeedChangeSupportRequired(audioOffloadPreferences["isSpeedChangeSupportRequired"] as Boolean)
                .setAudioOffloadMode(audioOffloadPreferences["audioOffloadMode"] as Int)
                .build()
        } else {
            val offloadMode = if (offloadEnabled) {
                AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED
            } else {
                AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_DISABLED
            }
            this.audioOffloadPreferences = AudioOffloadPreferences.Builder()
                .setIsGaplessSupportRequired(!offloadEnabled)
                .setIsSpeedChangeSupportRequired(!offloadEnabled)
                .setAudioOffloadMode(offloadMode)
                .build()
        }

        methodChannel.setMethodCallHandler(this)
        if (audioLoadConfiguration != null) {
            val loadControlMap = audioLoadConfiguration["androidLoadControl"] as Map<*, *>?
            if (loadControlMap != null) {
                val builder = DefaultLoadControl.Builder()
                    .setBufferDurationsMs(
                        (getLong(loadControlMap["minBufferDuration"])!! / 1000).toInt(),
                        (getLong(loadControlMap["maxBufferDuration"])!! / 1000).toInt(),
                        (getLong(loadControlMap["bufferForPlaybackDuration"])!! / 1000).toInt(),
                        (getLong(loadControlMap["bufferForPlaybackAfterRebufferDuration"])!! / 1000).toInt(),
                    )
                    .setPrioritizeTimeOverSizeThresholds(loadControlMap["prioritizeTimeOverSizeThresholds"] as Boolean)
                    .setBackBuffer((getLong(loadControlMap["backBufferDuration"])!! / 1000).toInt(), false)
                (loadControlMap["targetBufferBytes"] as Int?)?.let { builder.setTargetBufferBytes(it) }
                loadControl = builder.build()
            }
            val liveMap = audioLoadConfiguration["androidLivePlaybackSpeedControl"] as Map<*, *>?
            if (liveMap != null) {
                livePlaybackSpeedControl = DefaultLivePlaybackSpeedControl.Builder()
                    .setFallbackMinPlaybackSpeed((liveMap["fallbackMinPlaybackSpeed"] as Double).toFloat())
                    .setFallbackMaxPlaybackSpeed((liveMap["fallbackMaxPlaybackSpeed"] as Double).toFloat())
                    .setMinUpdateIntervalMs(getLong(liveMap["minUpdateInterval"])!! / 1000)
                    .setProportionalControlFactor((liveMap["proportionalControlFactor"] as Double).toFloat())
                    .setMaxLiveOffsetErrorMsForUnitSpeed(getLong(liveMap["maxLiveOffsetErrorForUnitSpeed"])!! / 1000)
                    .setTargetLiveOffsetIncrementOnRebufferMs(getLong(liveMap["targetLiveOffsetIncrementOnRebuffer"])!! / 1000)
                    .setMinPossibleLiveOffsetSmoothingFactor((liveMap["minPossibleLiveOffsetSmoothingFactor"] as Double).toFloat())
                    .build()
            }
        }
    }

    private fun startWatchingBuffer() {
        handler.removeCallbacks(bufferWatcher)
        handler.post(bufferWatcher)
    }

    override fun onIsLoadingChanged(isLoading: Boolean) {
        // Starting reads the buffer position again; stopping takes a final reading.
        startWatchingBuffer()
    }

    private fun updateAudioSessionId(newAudioSessionId: Int) {
        audioSessionId = if (newAudioSessionId == C.AUDIO_SESSION_ID_UNSET) null else newAudioSessionId
        clearAudioEffects()
        audioSessionId?.let { sessionId ->
            for (rawAudioEffect in rawAudioEffects) {
                val json = rawAudioEffect as Map<*, *>
                // Some devices do not provide an effect (or refuse it for this session); skip it rather than
                // leaving the player half set up.
                val audioEffect = try {
                    decodeAudioEffect(json, sessionId)
                } catch (e: RuntimeException) {
                    Log.e(TAG, "Could not create audio effect ${json["type"]}", e)
                    continue
                }
                if (json["enabled"] as Boolean) {
                    audioEffect.setEnabled(true)
                }
                audioEffects.add(audioEffect)
                audioEffectsMap[json["type"] as String] = audioEffect
            }
        }
        enqueuePlaybackEvent()
    }

    override fun onAudioSessionIdChanged(audioSessionId: Int) {
        updateAudioSessionId(audioSessionId)
        broadcastPendingPlaybackEvent()
    }

    override fun onMetadata(metadata: Metadata) {
        for (i in 0 until metadata.length()) {
            val entry = metadata[i]
            if (entry is IcyInfo) {
                icyInfo = entry
                cachedIcyMetadata = null
                broadcastImmediatePlaybackEvent()
            }
        }
    }

    override fun onTracksChanged(tracks: Tracks) {
        for (group in tracks.groups) {
            val trackGroup = group.mediaTrackGroup
            for (j in 0 until trackGroup.length) {
                val metadata = trackGroup.getFormat(j).metadata ?: continue
                for (k in 0 until metadata.length()) {
                    val entry = metadata[k]
                    if (entry is IcyHeaders) {
                        icyHeaders = entry
                        cachedIcyMetadata = null
                        broadcastImmediatePlaybackEvent()
                    }
                }
            }
        }
    }

    private fun updatePositionIfChanged(): Boolean {
        val player = exoPlayer ?: return false
        if (!player.playWhenReady || processingState != ProcessingState.ready) {
            if (currentPositionMs() == updatePosition) return false
        }
        updatePosition = currentPositionMs()
        updateTime = System.currentTimeMillis()
        return true
    }

    private fun updatePositionNow() {
        updatePosition = currentPositionMs()
        updateTime = System.currentTimeMillis()
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        updatePositionNow()
        when (reason) {
            Player.DISCONTINUITY_REASON_AUTO_TRANSITION,
            Player.DISCONTINUITY_REASON_SEEK -> updateCurrentIndex()
        }
        broadcastImmediatePlaybackEvent()
    }

    override fun onTimelineChanged(timeline: Timeline, reason: Int) {
        if (updateCurrentIndex()) {
            broadcastImmediatePlaybackEvent()
        }
        if (player.playbackState == Player.STATE_ENDED) {
            try {
                if (player.playWhenReady) {
                    if (lastPlaylistLength == 0 && player.mediaItemCount > 0) {
                        player.seekTo(0, 0L)
                    } else if (player.hasNextMediaItem()) {
                        player.seekToNextMediaItem()
                    }
                } else {
                    if (player.currentMediaItemIndex < player.mediaItemCount) {
                        player.seekTo(player.currentMediaItemIndex, 0L)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        lastPlaylistLength = player.mediaItemCount
    }

    private fun updateCurrentIndex(): Boolean {
        val newIndex = player.currentMediaItemIndex
        // newIndex is never null.
        // currentIndex is sometimes null.
        if (newIndex != currentIndex) {
            currentIndex = newIndex
            return true
        }
        return false
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_READY -> {
                if (player.playWhenReady) updatePositionNow()
                processingState = ProcessingState.ready
                errorCode = null
                errorMessage = null
                broadcastImmediatePlaybackEvent()
                completePrepare()
                if (seekResult != null) {
                    completeSeek()
                }
            }
            Player.STATE_BUFFERING -> {
                updatePositionIfChanged()
                if (processingState != ProcessingState.buffering && processingState != ProcessingState.loading) {
                    processingState = ProcessingState.buffering
                    errorCode = null
                    errorMessage = null
                    broadcastImmediatePlaybackEvent()
                }
                startWatchingBuffer()
            }
            Player.STATE_ENDED -> {
                if (processingState != ProcessingState.completed) {
                    updatePositionNow()
                    processingState = ProcessingState.completed
                    errorCode = null
                    errorMessage = null
                    broadcastImmediatePlaybackEvent()
                }
                completePrepare()
                playResult?.let {
                    it.success(emptyMap<String, Any?>())
                    playResult = null
                }
            }
        }
    }

    /**
     * ExoPlayer pauses itself when the audio focus is lost for good, when headphones are unplugged and when
     * playback stayed suppressed for too long. Dart owns the `playing` state, so it has to be told.
     */
    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        if (playWhenReady || reason == Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST) return
        updatePositionNow()
        enqueuePlaybackEvent()
        playResult?.let {
            it.success(emptyMap<String, Any?>())
            playResult = null
        }
        dataEventChannel.success(mapOf("playing" to false))
        broadcastPendingPlaybackEvent()
    }

    /** Completes a pending [load] call with the duration, then applies any deferred audio attributes. */
    private fun completePrepare() {
        val result = prepareResult ?: return
        result.success(mapOf("duration" to durationMicros()))
        prepareResult = null
        pendingAudioAttributes?.let {
            player.setAudioAttributes(it, handleInterruptions)
            pendingAudioAttributes = null
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        if (error is ExoPlaybackException) {
            when (error.type) {
                ExoPlaybackException.TYPE_SOURCE ->
                    Log.e(TAG, "TYPE_SOURCE: " + error.sourceException.message)
                ExoPlaybackException.TYPE_RENDERER ->
                    Log.e(TAG, "TYPE_RENDERER: " + error.rendererException.message)
                ExoPlaybackException.TYPE_UNEXPECTED ->
                    Log.e(TAG, "TYPE_UNEXPECTED: " + error.unexpectedException.message)
                // unexpectedException may only be read for TYPE_UNEXPECTED.
                else ->
                    Log.e(TAG, "default ExoPlaybackException: " + error.message)
            }
            // TODO: send both errorCode and type
            sendError(error.type, error.message, mapOf("index" to currentIndex))
        } else {
            Log.e(TAG, "default PlaybackException: " + error.message)
            sendError(error.errorCode, error.message, mapOf("index" to currentIndex))
        }
    }

    private fun completeSeek() {
        seekPos = null
        seekResult?.success(emptyMap<String, Any?>())
        seekResult = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            // Inside the try so a failure is reported to Dart and retried on the next call.
            ensurePlayerInitialized()
            when (call.method) {
                "load" -> {
                    val initialPosition = getLong(call.argument<Any>("initialPosition"))
                    val initialIndex = call.argument<Int>("initialIndex")
                    val audioSourceMap = call.argument<Map<*, *>>("audioSource")!!
                    val children = getAudioSources(audioSourceMap["children"])
                    // Forget sources from earlier playlists that this one no longer uses.
                    val usedIds = HashSet<String>()
                    collectAudioSourceIds(audioSourceMap, usedIds)
                    mediaSources.keys.retainAll(usedIds)
                    val shuffleOrder = decodeShuffleOrder(mapGet(audioSourceMap, "shuffleOrder")!!)
                    load(
                        children,
                        shuffleOrder,
                        if (initialPosition == null) C.TIME_UNSET else initialPosition / 1000,
                        initialIndex,
                        result,
                    )
                }
                "play" -> play(result)
                "pause" -> {
                    pause()
                    result.success(emptyMap<String, Any?>())
                }
                "setVolume" -> {
                    player.volume = call.argument<Double>("volume")!!.toFloat()
                    result.success(emptyMap<String, Any?>())
                }
                "setSpeed" -> {
                    setSpeed(call.argument<Double>("speed")!!.toFloat())
                    result.success(emptyMap<String, Any?>())
                }
                "setPitch" -> {
                    setPitch(call.argument<Double>("pitch")!!.toFloat())
                    result.success(emptyMap<String, Any?>())
                }
                "setSkipSilence" -> {
                    player.setSkipSilenceEnabled(call.argument<Boolean>("enabled")!!)
                    result.success(emptyMap<String, Any?>())
                }
                "setLoopMode" -> {
                    player.repeatMode = call.argument<Int>("loopMode")!!
                    result.success(emptyMap<String, Any?>())
                }
                "setShuffleMode" -> {
                    player.setShuffleModeEnabled(call.argument<Int>("shuffleMode") == 1)
                    result.success(emptyMap<String, Any?>())
                }
                "setShuffleOrder" -> {
                    val playlist = call.argument<Map<*, *>>("audioSource")!!
                    player.setShuffleOrder(decodeShuffleOrder(mapGet(playlist, "shuffleOrder")!!))
                    result.success(emptyMap<String, Any?>())
                }
                "setAutomaticallyWaitsToMinimizeStalling",
                "setCanUseNetworkResourcesForLiveStreamingWhilePaused",
                "setPreferredPeakBitRate" -> result.success(emptyMap<String, Any?>())
                "seek" -> {
                    val position = getLong(call.argument<Any>("position"))
                    val index = call.argument<Int>("index")
                    seek(if (position == null) C.TIME_UNSET else position / 1000, index, result)
                }
                // The playlist is always the root one, which maps onto ExoPlayer's
                // own playlist.
                "concatenatingInsertAll" -> {
                    val index = call.argument<Int>("index")!!
                    val children = getAudioSources(call.argument<Any>("children"))
                    player.addMediaSources(index, children)
                    player.setShuffleOrder(decodeShuffleOrder(call.argument<List<Int>>("shuffleOrder")!!))
                    result.success(emptyMap<String, Any?>())
                }
                "concatenatingRemoveRange" -> {
                    player.removeMediaItems(call.argument<Int>("startIndex")!!, call.argument<Int>("endIndex")!!)
                    player.setShuffleOrder(decodeShuffleOrder(call.argument<List<Int>>("shuffleOrder")!!))
                    result.success(emptyMap<String, Any?>())
                }
                "concatenatingMove" -> {
                    player.moveMediaItem(call.argument<Int>("currentIndex")!!, call.argument<Int>("newIndex")!!)
                    player.setShuffleOrder(decodeShuffleOrder(call.argument<List<Int>>("shuffleOrder")!!))
                    result.success(emptyMap<String, Any?>())
                }
                "setAndroidAudioAttributes" -> {
                    setAudioAttributes(
                        call.argument<Int>("contentType")!!,
                        call.argument<Int>("flags")!!,
                        call.argument<Int>("usage")!!,
                    )
                    result.success(emptyMap<String, Any?>())
                }
                "audioEffectSetEnabled" -> {
                    audioEffectsMap[call.argument<String>("type")!!]
                        ?.setEnabled(call.argument<Boolean>("enabled")!!)
                    result.success(emptyMap<String, Any?>())
                }
                "androidLoudnessEnhancerSetTargetGain" -> {
                    val targetGain = call.argument<Number>("targetGain")?.toDouble() ?: 0.0
                    loudnessEnhancerSetTargetGain(targetGain)
                    result.success(emptyMap<String, Any?>())
                }
                "androidEqualizerGetParameters" -> result.success(equalizerAudioEffectGetParameters())
                "androidEqualizerBandSetGain" -> {
                    val gain = call.argument<Number>("gain")?.toDouble() ?: 0.0
                    equalizerBandSetGain(call.argument<Int>("bandIndex")!!, gain)
                    result.success(emptyMap<String, Any?>())
                }
                else -> result.notImplemented()
            }
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Illegal state in ${call.method}", e)
            result.error(ERROR_ILLEGAL_STATE, e.message ?: e.toString(), e.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Error in ${call.method}", e)
            result.error(ERROR_GENERIC, e.message ?: e.toString(), e.toString())
        } finally {
            broadcastPendingPlaybackEvent()
        }
    }

    private fun decodeShuffleOrder(indexList: List<Int>): ShuffleOrder =
        DefaultShuffleOrder(indexList.toIntArray(), random.nextLong())

    private fun getAudioSource(json: Any?): MediaSource {
        val map = json as Map<*, *>
        val id = map["id"] as String
        return mediaSources.getOrPut(id) { decodeAudioSource(map) }
    }

    // Shared by every source that does not customise its headers or extractor
    // options, so large playlists do not allocate one factory per item.
    private val defaultDataSourceFactory: DataSource.Factory by lazy { createDataSourceFactory(null) }
    private val defaultExtractorsFactory: DefaultExtractorsFactory by lazy { createExtractorsFactory(null) }

    private fun buildExtractorsFactory(options: Map<*, *>?): DefaultExtractorsFactory =
        if (options?.get("androidExtractorOptions") == null) defaultExtractorsFactory else createExtractorsFactory(options)

    private fun createExtractorsFactory(options: Map<*, *>?): DefaultExtractorsFactory {
        var constantBitrateSeekingEnabled = true
        var constantBitrateSeekingAlwaysEnabled = false
        var mp3Flags = 0
        val androidExtractorOptions = options?.get("androidExtractorOptions") as Map<*, *>?
        if (androidExtractorOptions != null) {
            constantBitrateSeekingEnabled = androidExtractorOptions["constantBitrateSeekingEnabled"] as Boolean
            constantBitrateSeekingAlwaysEnabled = androidExtractorOptions["constantBitrateSeekingAlwaysEnabled"] as Boolean
            mp3Flags = androidExtractorOptions["mp3Flags"] as Int
        }
        return DefaultExtractorsFactory().apply {
            setConstantBitrateSeekingEnabled(constantBitrateSeekingEnabled)
            setConstantBitrateSeekingAlwaysEnabled(constantBitrateSeekingAlwaysEnabled)
            setMp3ExtractorFlags(mp3Flags)
        }
    }

    private fun decodeAudioSource(map: Map<*, *>): MediaSource {
        val id = map["id"] as String
        return when (val type = map["type"] as String) {
            "progressive" -> ProgressiveMediaSource.Factory(
                buildDataSourceFactory(mapGet(map, "headers")),
                buildExtractorsFactory(mapGet(map, "options")),
            ).createMediaSource(
                MediaItem.Builder()
                    .setUri(Uri.parse(map["uri"] as String))
                    .setTag(id)
                    .build(),
            )
            "dash" -> DashMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                .createMediaSource(
                    MediaItem.Builder()
                        .setUri(Uri.parse(map["uri"] as String))
                        .setMimeType(MimeTypes.APPLICATION_MPD)
                        .setTag(id)
                        .build(),
                )
            "hls" -> HlsMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                .createMediaSource(
                    MediaItem.Builder()
                        .setUri(Uri.parse(map["uri"] as String))
                        .setMimeType(MimeTypes.APPLICATION_M3U8)
                        .build(),
                )
            "silence" -> SilenceMediaSource.Factory()
                .setDurationUs(getLong(map["duration"])!!)
                .setTag(id)
                .createMediaSource()
            "clipping" -> ClippingMediaSource.Builder(getAudioSource(map["child"]))
                .setStartPositionUs(getLong(map["start"]) ?: 0L)
                .setEndPositionUs(getLong(map["end"]) ?: C.TIME_END_OF_SOURCE)
                .build()
            else -> throw IllegalArgumentException("Unknown AudioSource type: $type")
        }
    }

    private fun collectAudioSourceIds(json: Any?, ids: MutableSet<String>) {
        val map = json as? Map<*, *> ?: return
        (map["id"] as? String)?.let { ids.add(it) }
        (map["children"] as? List<*>)?.forEach { collectAudioSourceIds(it, ids) }
        collectAudioSourceIds(map["child"], ids)
    }

    private fun getAudioSources(json: Any?): List<MediaSource> {
        if (json !is List<*>) throw RuntimeException("List expected: $json")
        return json.map { getAudioSource(it) }
    }

    private fun decodeAudioEffect(map: Map<*, *>, audioSessionId: Int): AudioEffect =
        when (val type = map["type"] as String) {
            "AndroidLoudnessEnhancer" -> {
                // target gain needs to be provided in milliBel, the user provides the value in deciBel
                val rawGain = (map["targetGain"] as? Number)?.toDouble() ?: 0.0
                val targetGain = Math.round(rawGain * 100.0).toInt()
                LoudnessEnhancer(audioSessionId).apply { setTargetGain(targetGain) }
            }
            "AndroidEqualizer" -> Equalizer(0, audioSessionId)
            else -> throw IllegalArgumentException("Unknown AudioEffect type: $type")
        }

    private fun clearAudioEffects() {
        audioEffects.forEach { it.release() }
        audioEffects.clear()
        audioEffectsMap.clear()
    }

    private fun buildDataSourceFactory(headers: Map<*, *>?): DataSource.Factory =
        if (headers.isNullOrEmpty()) defaultDataSourceFactory else createDataSourceFactory(headers)

    private fun createDataSourceFactory(headers: Map<*, *>?): DataSource.Factory {
        val stringHeaders = castToStringMap(headers)
        var userAgent: String? = null
        if (stringHeaders != null) {
            userAgent = stringHeaders.remove("User-Agent") ?: stringHeaders.remove("user-agent")
        }
        if (userAgent == null) {
            userAgent = Util.getUserAgent(context, "audio_player")
        }
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
        if (!stringHeaders.isNullOrEmpty()) {
            httpDataSourceFactory.setDefaultRequestProperties(stringHeaders)
        }
        return DefaultDataSource.Factory(context, httpDataSourceFactory)
    }

    private fun load(
        mediaSources: List<MediaSource>,
        shuffleOrder: ShuffleOrder,
        initialPosition: Long,
        initialIndex: Int?,
        result: Result,
    ) {
        currentIndex = initialIndex ?: 0
        when (processingState) {
            ProcessingState.idle -> {}
            ProcessingState.loading -> {
                abortExistingConnection(false)
                player.stop()
            }
            else -> player.stop()
        }
        prepareResult = result
        updatePositionNow()
        processingState = ProcessingState.loading
        errorCode = null
        errorMessage = null
        enqueuePlaybackEvent()
        player.setMediaSources(mediaSources, initialIndex ?: 0, initialPosition)
        player.setShuffleOrder(shuffleOrder)
        player.prepare()
    }

    private fun ensurePlayerInitialized() {
        if (exoPlayer != null) return
        val renderersFactory = RenderersFactory { eventHandler, videoListener, audioListener, textOutput, metadataOutput ->
            val defaultRenderers: Array<Renderer> = DefaultRenderersFactory(context)
                .createRenderers(eventHandler, videoListener, audioListener, textOutput, metadataOutput)
            defaultRenderers + ObserverRenderer()
        }
        val builder = ExoPlayer.Builder(context, renderersFactory)
        builder.setUseLazyPreparation(useLazyPreparation)
        // ExoPlayer requests the audio focus while playing, ducks or pauses when another app takes it
        // temporarily and resumes when it returns, and pauses when headphones are unplugged. The audio
        // attributes can be replaced later by setAndroidAudioAttributes.
        builder.setAudioAttributes(AudioAttributes.DEFAULT, handleInterruptions)
        builder.setHandleAudioBecomingNoisy(handleInterruptions)
        loadControl?.let { builder.setLoadControl(it) }
        livePlaybackSpeedControl?.let { builder.setLivePlaybackSpeedControl(it) }
        val newPlayer = builder.build()
        newPlayer.trackSelectionParameters = newPlayer.trackSelectionParameters
            .buildUpon()
            .setAudioOffloadPreferences(audioOffloadPreferences)
            .build()
        // Listen before anything else can fail, so the player never ends up created but silent.
        newPlayer.addListener(this)
        exoPlayer = newPlayer
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val generatedSessionId = audioManager?.generateAudioSessionId() ?: C.AUDIO_SESSION_ID_UNSET
        if (generatedSessionId != C.AUDIO_SESSION_ID_UNSET && generatedSessionId != AudioManager.ERROR) {
            newPlayer.setAudioSessionId(generatedSessionId)
        }
        updateAudioSessionId(newPlayer.audioSessionId)
    }

    private fun setAudioAttributes(contentType: Int, flags: Int, usage: Int) {
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(contentType)
            .setFlags(flags)
            .setUsage(usage)
            .build()
        if (processingState == ProcessingState.loading) {
            // audio attributes should be set either before or after loading to
            // avoid an ExoPlayer glitch.
            pendingAudioAttributes = audioAttributes
        } else {
            player.setAudioAttributes(audioAttributes, handleInterruptions)
        }
    }

    private fun loudnessEnhancerSetTargetGain(targetGain: Double) {
        // target gain needs to be provided in milliBel, the user provides the value in deciBel
        val targetGainMillibels = Math.round(targetGain * 100.0).toInt()
        (audioEffectsMap["AndroidLoudnessEnhancer"] as? LoudnessEnhancer)?.setTargetGain(targetGainMillibels)
    }

    private fun equalizerAudioEffectGetParameters(): Map<String, Any?> {
        val equalizer = audioEffectsMap["AndroidEqualizer"] as? Equalizer
            ?: return mapOf(
                "parameters" to mapOf(
                    "minDecibels" to 0.0,
                    "maxDecibels" to 0.0,
                    "bands" to emptyList<Map<String, Any?>>(),
                ),
            )
        val rawBands = ArrayList<Any?>()
        for (i in 0 until equalizer.numberOfBands.toInt()) {
            val band = i.toShort()
            val freqRange = equalizer.getBandFreqRange(band)
            // Frequencies are returned in milliHertz, we want Hertz.
            rawBands.add(
                mapOf(
                    "index" to i,
                    "lowerFrequency" to freqRange[0].toDouble() / 1000.0,
                    "upperFrequency" to freqRange[1].toDouble() / 1000.0,
                    "centerFrequency" to equalizer.getCenterFreq(band).toDouble() / 1000.0,
                    // returns a value in milliBel, we want deciBel
                    "gain" to equalizer.getBandLevel(band) / 100.0,
                ),
            )
        }
        val levelRange = equalizer.bandLevelRange
        return mapOf(
            "parameters" to mapOf(
                // returns a value in milliBel, we want deciBel
                "minDecibels" to levelRange[0] / 100.0,
                "maxDecibels" to levelRange[1] / 100.0,
                "bands" to rawBands,
            ),
        )
    }

    private fun equalizerBandSetGain(bandIndex: Int, gain: Double) {
        // target gain needs to be provided in milliBel, the user provides the value in deciBel
        (audioEffectsMap["AndroidEqualizer"] as? Equalizer)
            ?.setBandLevel(bandIndex.toShort(), Math.round(gain * 100.0).toShort())
    }

    /** Creates an event based on the current state. */
    private fun createPlaybackEvent(): Map<String, Any?> {
        bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
        return hashMapOf(
            "processingState" to processingState.ordinal,
            "updatePosition" to 1000 * updatePosition,
            "updateTime" to updateTime,
            "bufferedPosition" to 1000 * maxOf(updatePosition, bufferedPosition),
            "icyMetadata" to collectIcyMetadata(),
            "duration" to durationMicros(),
            "currentIndex" to currentIndex,
            "androidAudioSessionId" to audioSessionId,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
        )
    }

    // Broadcast the pending playback event if it was set.
    private fun broadcastPendingPlaybackEvent() {
        pendingPlaybackEvent?.let {
            eventChannel.success(it)
            pendingPlaybackEvent = null
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
    private fun enqueuePlaybackEvent() {
        pendingPlaybackEvent = createPlaybackEvent()
    }

    // Broadcasts a new event immediately.
    private fun broadcastImmediatePlaybackEvent() {
        enqueuePlaybackEvent()
        broadcastPendingPlaybackEvent()
    }

    // Playback events are sent often but the ICY metadata rarely changes, so the
    // encoded map is built once and reused until the metadata changes.
    private fun collectIcyMetadata(): Map<String, Any?> =
        cachedIcyMetadata ?: buildIcyMetadata().also { cachedIcyMetadata = it }

    private fun buildIcyMetadata(): Map<String, Any?> {
        val icyData = HashMap<String, Any?>()
        icyInfo?.let {
            icyData["info"] = hashMapOf("title" to it.title, "url" to it.url)
        }
        icyHeaders?.let {
            icyData["headers"] = hashMapOf(
                "bitrate" to it.bitrate,
                "genre" to it.genre,
                "name" to it.name,
                "metadataInterval" to it.metadataInterval,
                "url" to it.url,
                "isPublic" to it.isPublic,
            )
        }
        return icyData
    }

    private fun currentPositionMs(): Long {
        val sp = seekPos
        return if (processingState == ProcessingState.idle || processingState == ProcessingState.loading) {
            maxOf(player.currentPosition, 0L)
        } else if (sp != null && sp != C.TIME_UNSET) {
            sp
        } else {
            player.currentPosition
        }
    }

    private fun durationMs(): Long =
        if (processingState == ProcessingState.idle || processingState == ProcessingState.loading || exoPlayer == null) {
            C.TIME_UNSET
        } else {
            player.duration
        }

    /** The duration in microseconds as expected by Dart, or null if unknown. */
    private fun durationMicros(): Long? {
        val duration = durationMs()
        return if (duration == C.TIME_UNSET) null else 1000 * duration
    }

    private fun sendError(errorCode: Int, errorMsg: String?, details: Any?, switchToIdle: Boolean = true) {
        eventChannel.error(errorCode.toString(), errorMsg, details)
        this.errorCode = errorCode
        this.errorMessage = errorMsg
        if (switchToIdle) {
            processingState = ProcessingState.idle
        }
        broadcastImmediatePlaybackEvent()
        prepareResult?.let {
            it.error(errorCode.toString(), errorMsg, details)
            prepareResult = null
        }
    }

    private fun play(result: Result) {
        if (player.playWhenReady) {
            result.success(emptyMap<String, Any?>())
            return
        }
        playResult?.success(emptyMap<String, Any?>())
        playResult = result
        player.playWhenReady = true
        updatePositionNow()
        if (processingState == ProcessingState.completed) {
            playResult?.success(emptyMap<String, Any?>())
            playResult = null
        }
    }

    private fun pause() {
        if (!player.playWhenReady) return
        player.playWhenReady = false
        updatePositionNow()
        enqueuePlaybackEvent()
        playResult?.let {
            it.success(emptyMap<String, Any?>())
            playResult = null
        }
    }

    private fun setSpeed(speed: Float) {
        val params = player.playbackParameters
        if (params.speed == speed) return
        player.playbackParameters = PlaybackParameters(speed, params.pitch)
        if (player.playWhenReady) updatePositionNow()
        enqueuePlaybackEvent()
    }

    private fun setPitch(pitch: Float) {
        val params = player.playbackParameters
        if (params.pitch == pitch) return
        player.playbackParameters = PlaybackParameters(params.speed, pitch)
        enqueuePlaybackEvent()
    }

    private fun seek(position: Long, index: Int?, result: Result) {
        if (processingState == ProcessingState.idle || processingState == ProcessingState.loading) {
            result.success(emptyMap<String, Any?>())
            return
        }
        abortSeek()
        seekPos = position
        seekResult = result
        try {
            player.seekTo(index ?: player.currentMediaItemIndex, position)
        } catch (e: RuntimeException) {
            seekResult = null
            seekPos = null
            throw e
        }
    }

    fun dispose() {
        if (processingState == ProcessingState.loading) {
            abortExistingConnection(true)
        }
        playResult?.let {
            it.success(emptyMap<String, Any?>())
            playResult = null
        }
        abortSeek()
        handler.removeCallbacksAndMessages(null)
        mediaSources.clear()
        clearAudioEffects()
        exoPlayer?.let {
            it.release()
            exoPlayer = null
            processingState = ProcessingState.idle
            broadcastImmediatePlaybackEvent()
        }
        // Unregister the channels. Otherwise the messenger keeps this disposed
        // player (and its three handlers) alive for the rest of the engine's life.
        methodChannel.setMethodCallHandler(null)
        eventChannel.dispose()
        dataEventChannel.dispose()
    }

    private fun abortSeek() {
        seekResult?.let {
            try {
                it.success(emptyMap<String, Any?>())
            } catch (e: RuntimeException) {
                // Result already sent
            }
            seekResult = null
            seekPos = null
        }
    }

    private fun abortExistingConnection(switchToIdle: Boolean) {
        sendError(ERROR_ABORT, "Connection aborted", null, switchToIdle)
    }

    private inner class ObserverRenderer : NoSampleRenderer() {
        private var lastPosUs = 0L
        private var consecutivePosCount = 0

        override fun render(positionUs: Long, elapsedRealtimeUs: Long) {
            if (positionUs == lastPosUs) {
                consecutivePosCount++
            } else {
                if (consecutivePosCount >= 3) {
                    handler.post {
                        if (updatePositionIfChanged()) {
                            broadcastImmediatePlaybackEvent()
                        }
                    }
                }
                consecutivePosCount = 0
            }
            lastPosUs = positionUs
        }

        override fun getName(): String = "ObserverRenderer"
    }

    companion object {
        const val ERROR_ABORT = 10000000
        // Stable, machine-readable codes for errors raised by method calls.
        private const val ERROR_ILLEGAL_STATE = "illegal_state"
        private const val ERROR_GENERIC = "error"
        private const val TAG = "AudioPlayer"

        private val random = Random()

        // Dart can't distinguish between int sizes so
        // Flutter may send us a Long or an Integer
        // depending on the number of bits required to
        // represent it.
        private fun getLong(o: Any?): Long? = when (o) {
            null -> null
            is Long -> o
            else -> (o as Int).toLong()
        }

        @Suppress("UNCHECKED_CAST")
        private fun <T> mapGet(o: Any?, key: String): T? = (o as? Map<*, *>)?.get(key) as T?

        private fun castToStringMap(map: Map<*, *>?): MutableMap<String, String>? =
            map?.entries?.associateTo(HashMap()) { it.key as String to it.value as String }
    }
}
