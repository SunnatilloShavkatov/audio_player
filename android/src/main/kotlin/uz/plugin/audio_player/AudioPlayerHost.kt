package uz.plugin.audio_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.Log

/**
 * The players of one attached Flutter engine, behind [AudioPlayerApi]. Players are used on the main thread only:
 * Dart already runs there (merged UI/platform thread), and calls from elsewhere are posted. Once [detach]ed, or
 * after [restart], the host delivers nothing more, so the events of a gone engine never reach a new one.
 */
internal class AudioPlayerHost(private val applicationContext: Context) {

    companion object {
        /** The host of the attached engine; `null` while none is attached. */
        @Volatile
        var current: AudioPlayerHost? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        private const val TAG = "AudioPlayerHost"

        private fun onMain(block: () -> Unit) {
            if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
        }
    }

    @Volatile
    private var attached = true

    @Volatile
    private var listener: AudioPlayerApi.PlaybackListener? = null

    // Touched on the main thread only.
    private val players = HashMap<String, AudioPlayer>()

    fun setListener(newListener: AudioPlayerApi.PlaybackListener?) {
        listener = newListener
    }

    /** Runs a plugin-level call (`init`, `disposePlayer`, `disposeAllPlayers`). */
    fun call(method: String, request: String?, callback: AudioPlayerApi.ResultCallback) {
        val result = CallbackResult(callback)
        onMain {
            if (!attached) {
                result.error(ErrorCode.DETACHED, "No Flutter engine is attached", null)
                return@onMain
            }
            try {
                handleCall(PlayerCall(method, JsonCodec.decodeMap(request)), result)
            } catch (e: InvalidArgumentException) {
                result.error(ErrorCode.INVALID_ARGUMENT, e.message, null)
            } catch (e: Exception) {
                // Never let an exception escape into the engine: report it to Dart instead.
                Log.e(TAG, "Failed to handle $method", e)
                result.error(ErrorCode.GENERIC, e.message ?: e.toString(), null)
            }
        }
    }

    /** Runs a call on the player [playerId]. */
    fun callPlayer(playerId: String, method: String, request: String?, callback: AudioPlayerApi.ResultCallback) {
        val result = CallbackResult(callback)
        onMain {
            val player = players[playerId]
            if (!attached || player == null) {
                result.error(ErrorCode.GENERIC, "Platform player $playerId does not exist", null)
                return@onMain
            }
            try {
                player.handleCall(PlayerCall(method, JsonCodec.decodeMap(request)), result)
            } catch (e: InvalidArgumentException) {
                result.error(ErrorCode.INVALID_ARGUMENT, e.message, null)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to handle $method", e)
                result.error(ErrorCode.GENERIC, e.message ?: e.toString(), null)
            }
        }
    }

    private fun handleCall(call: PlayerCall, result: PlayerResult) {
        when (call.method) {
            "init" -> init(call, result)
            "disposePlayer" -> {
                call.arguments.optional<String>("id")?.let { players.remove(it)?.dispose(calledFromDeinit = false) }
                result.success(emptyMap<String, Any?>())
            }
            "disposeAllPlayers" -> {
                dispose(calledFromDeinit = false)
                result.success(emptyMap<String, Any?>())
            }
            else -> result.error(ErrorCode.UNIMPLEMENTED, "Unknown method ${call.method}", null)
        }
    }

    private fun init(call: PlayerCall, result: PlayerResult) {
        val id = call.arguments.optional<String>("id")
        if (id == null) {
            result.error(ErrorCode.INVALID_ARGUMENT, "Missing player id", null)
            return
        }
        if (players.containsKey(id)) {
            result.error(ErrorCode.GENERIC, "Platform player $id already exists", null)
            return
        }
        players[id] = AudioPlayer(
            applicationContext,
            EventSink(id),
            call.arguments.optional<Map<*, *>>("audioLoadConfiguration"),
            call.arguments.optional<List<Any?>>("androidAudioEffects") ?: emptyList(),
            call.arguments.optional<Map<*, *>>("androidAudioOffloadPreferences"),
            call.arguments.optional<Boolean>("androidOffloadSchedulingEnabled"),
            call.arguments.optional<Boolean>("useLazyPreparation") ?: true,
            call.arguments.optional<Boolean>("handleInterruptions") ?: true,
        )
        result.success(emptyMap<String, Any?>())
    }

    /**
     * Disposes every player. [calledFromDeinit] is true while the FlutterEngine is being destroyed or restarted,
     * when nothing may be sent; explicit disposal from Dart passes false.
     */
    fun dispose(calledFromDeinit: Boolean) {
        for (player in players.values.toList()) {
            // One failing player must not keep the others alive.
            try {
                player.dispose(calledFromDeinit)
            } catch (e: RuntimeException) {
                Log.e(TAG, "Failed to dispose a player", e)
            }
        }
        players.clear()
    }

    /** The engine restarts (hot restart): the Dart side is gone, so release the players and forget its listener. */
    fun restart() {
        listener = null
        dispose(calledFromDeinit = true)
    }

    /** The engine is destroyed: release the players, and nothing is delivered or answered from now on. */
    fun detach() {
        attached = false
        listener = null
        dispose(calledFromDeinit = true)
    }

    /** What one player reports to Dart, delivered to the current listener while the host is attached. */
    private inner class EventSink(private val playerId: String) : PlayerEventSink {
        @Volatile
        private var closed = false

        override fun playbackEvent(event: Map<String, Any?>) =
            deliver { it.onPlaybackEvent(playerId, JsonCodec.encode(event)) }

        override fun playbackError(code: String, message: String?, details: Any?) =
            deliver { it.onPlaybackError(playerId, code, message, JsonCodec.encodeDetails(details)) }

        override fun playerData(data: Map<String, Any?>) =
            deliver { it.onPlayerData(playerId, JsonCodec.encode(data)) }

        override fun close() {
            closed = true
        }

        private inline fun deliver(send: (AudioPlayerApi.PlaybackListener) -> Unit) {
            if (!attached || closed) return
            val target = listener ?: return
            try {
                send(target)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to deliver an event", e)
            }
        }
    }
}
