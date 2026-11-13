package uz.plugin.audio_player

import io.flutter.Log

/** A call from Dart: the [method] and its decoded request fields, read with the `require*` functions. */
internal class PlayerCall(val method: String, val arguments: Map<String, Any?>)

/** Where the answer to a [PlayerCall] goes. */
internal interface PlayerResult {
    fun success(value: Any?)

    fun error(code: String, message: String?, details: Any?)
}

/** Answers a call through its JNI callback. Only the first answer counts, later ones are dropped. */
internal class CallbackResult(private val callback: AudioPlayerApi.ResultCallback) : PlayerResult {
    private var replied = false

    override fun success(value: Any?) {
        if (!claim()) return
        val json = try {
            JsonCodec.encode(value)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to encode a reply", e)
            callback.onError(ErrorCode.GENERIC, e.message ?: e.toString(), null)
            return
        }
        callback.onResult(json)
    }

    override fun error(code: String, message: String?, details: Any?) {
        if (!claim()) return
        callback.onError(code, message, JsonCodec.encodeDetails(details))
    }

    private fun claim(): Boolean {
        if (replied) {
            Log.w(TAG, "A call was answered more than once")
            return false
        }
        replied = true
        return true
    }

    private companion object {
        const val TAG = "CallbackResult"
    }
}

/** Receives what a player reports to Dart. After the player is closed nothing is delivered. */
internal interface PlayerEventSink {
    fun playbackEvent(event: Map<String, Any?>)

    /** An error on the playback event stream; the next playback event carries it too. */
    fun playbackError(code: String, message: String?, details: Any?)

    fun playerData(data: Map<String, Any?>)

    /** Stops all delivery. */
    fun close()
}
