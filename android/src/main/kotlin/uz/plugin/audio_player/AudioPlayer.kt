package uz.plugin.audio_player

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LivePlaybackSpeedControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RenderersFactory
import io.flutter.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

internal enum class ProcessingState {
    idle,
    loading,
    buffering,
    ready,
    completed,
}

/**
 * One native player, driven over its own method channel.
 *
 * The work is split over several files that share this class's state: [AudioPlayerMethodHandler] decodes the method
 * calls, `AudioPlayerCommands.kt` runs them, [PlayerEventListener] reacts to ExoPlayer and `PlaybackEvents.kt`
 * reports the state to Dart.
 */
class AudioPlayer(
    applicationContext: Context,
    messenger: BinaryMessenger,
    id: String,
    audioLoadConfiguration: Map<*, *>?,
    rawAudioEffects: List<Any?>,
    audioOffloadPreferences: Map<*, *>?,
    offloadSchedulingEnabled: Boolean?,
    private val useLazyPreparation: Boolean,
    internal val handleInterruptions: Boolean,
) {
    internal val context: Context = applicationContext
    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "uz.plugin.audio_player.methods.$id")
    internal val eventChannel = BetterEventChannel(messenger, "uz.plugin.audio_player.events.$id")
    internal val dataEventChannel = BetterEventChannel(messenger, "uz.plugin.audio_player.data.$id")
    private val playerListener = PlayerEventListener(this)

    internal var processingState = ProcessingState.idle
    internal var updatePosition = 0L
    internal var updateTime = 0L
    internal var bufferedPosition = 0L
    internal var seekPos: Long? = null
    internal var prepareResult: Result? = null
    internal var playResult: Result? = null
    internal var seekResult: Result? = null
    internal val audioSources = AudioSourceDecoder(applicationContext)
    internal val icyMetadata = IcyMetadata()
    internal var pendingAudioAttributes: AudioAttributes? = null
    private val audioOffloadPreferences: AudioOffloadPreferences =
        buildAudioOffloadPreferences(audioOffloadPreferences, offloadSchedulingEnabled ?: false)
    private val loadControl: LoadControl? =
        releaseChannelsOnError { buildLoadControl(audioLoadConfiguration) }
    private val livePlaybackSpeedControl: LivePlaybackSpeedControl? =
        releaseChannelsOnError { buildLivePlaybackSpeedControl(audioLoadConfiguration) }
    internal val audioEffects = AudioEffectsController(rawAudioEffects)
    internal var lastPlaylistLength = 0
    internal var pendingPlaybackEvent: Map<String, Any?>? = null

    internal var exoPlayer: ExoPlayer? = null
    internal val player: ExoPlayer get() = exoPlayer!!
    internal var audioSessionId: Int? = null
    internal var errorCode: Int? = null
    internal var errorMessage: String? = null
    internal var currentIndex: Int? = null
    internal val handler = Handler(Looper.getMainLooper())

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
        // The configuration is parsed above, before the method handler is registered.
        methodChannel.setMethodCallHandler(AudioPlayerMethodHandler(this))
    }

    /**
     * Runs [block] while the configuration is parsed. A bad configuration throws, and the stream handlers of the
     * channels created above must not stay registered for a player that never existed.
     */
    private inline fun <T> releaseChannelsOnError(block: () -> T): T =
        try {
            block()
        } catch (e: Exception) {
            eventChannel.dispose(calledFromDeinit = false)
            dataEventChannel.dispose(calledFromDeinit = false)
            throw e
        }

    internal fun startWatchingBuffer() {
        handler.removeCallbacks(bufferWatcher)
        handler.post(bufferWatcher)
    }

    internal fun updateAudioSessionId(newAudioSessionId: Int) {
        audioSessionId = if (newAudioSessionId == C.AUDIO_SESSION_ID_UNSET) null else newAudioSessionId
        audioEffects.attach(audioSessionId)
        enqueuePlaybackEvent()
    }

    internal fun ensurePlayerInitialized() {
        if (exoPlayer != null) return
        val renderersFactory = RenderersFactory { eventHandler, videoListener, audioListener, textOutput, metadataOutput ->
            val defaultRenderers: Array<Renderer> = DefaultRenderersFactory(context)
                .createRenderers(eventHandler, videoListener, audioListener, textOutput, metadataOutput)
            defaultRenderers + ObserverRenderer(handler) {
                if (updatePositionIfChanged()) {
                    broadcastImmediatePlaybackEvent()
                }
            }
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
        newPlayer.addListener(playerListener)
        exoPlayer = newPlayer
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val generatedSessionId = audioManager?.generateAudioSessionId() ?: C.AUDIO_SESSION_ID_UNSET
        if (generatedSessionId != C.AUDIO_SESSION_ID_UNSET && generatedSessionId != AudioManager.ERROR) {
            newPlayer.setAudioSessionId(generatedSessionId)
        }
        updateAudioSessionId(newPlayer.audioSessionId)
    }

    /**
     * Releases the player and unregisters the channels.
     *
     * [calledFromDeinit] is true while the FlutterEngine is being destroyed or restarted. Then nothing may be sent
     * (replies to pending calls, playback events, end-of-stream) and the channel handlers are left alone, because
     * the engine drops them itself. Explicit disposal from Dart passes false and may send and unregister.
     */
    fun dispose(calledFromDeinit: Boolean) {
        if (!calledFromDeinit) {
            // A failing reply must not stop the release below, or ExoPlayer and the channels would leak.
            try {
                if (processingState == ProcessingState.loading) {
                    abortExistingConnection(true)
                }
                val pendingPlay = playResult
                playResult = null
                pendingPlay?.success(emptyMap<String, Any?>())
                abortSeek()
            } catch (e: RuntimeException) {
                Log.e(TAG, "Failed to reply to pending calls while disposing", e)
            }
        }
        prepareResult = null
        playResult = null
        seekResult = null
        seekPos = null
        handler.removeCallbacksAndMessages(null)
        audioSources.clear()
        audioEffects.clear()
        exoPlayer?.let {
            it.removeListener(playerListener)
            it.release()
            exoPlayer = null
            processingState = ProcessingState.idle
            if (!calledFromDeinit) {
                try {
                    broadcastImmediatePlaybackEvent()
                } catch (e: RuntimeException) {
                    Log.e(TAG, "Failed to send the final playback event", e)
                }
            }
        }
        pendingPlaybackEvent = null
        if (!calledFromDeinit) {
            // Unregister the channels. Otherwise the messenger keeps this disposed
            // player (and its three handlers) alive for the rest of the engine's life.
            methodChannel.setMethodCallHandler(null)
        }
        eventChannel.dispose(calledFromDeinit)
        dataEventChannel.dispose(calledFromDeinit)
    }

    companion object {
        const val ERROR_ABORT = 10000000
        internal const val TAG = "AudioPlayer"
    }
}
