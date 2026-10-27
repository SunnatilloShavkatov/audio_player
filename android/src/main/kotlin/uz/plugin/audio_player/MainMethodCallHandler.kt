package uz.plugin.audio_player

import android.content.Context
import io.flutter.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class MainMethodCallHandler(
    private val applicationContext: Context,
    private val messenger: BinaryMessenger,
) : MethodCallHandler {
    private val players = HashMap<String, AudioPlayer>()

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "init" -> init(call, result)
                "disposePlayer" -> {
                    call.argument<String>("id")?.let { players.remove(it)?.dispose(calledFromDeinit = false) }
                    result.success(emptyMap<String, Any?>())
                }
                "disposeAllPlayers" -> {
                    dispose(calledFromDeinit = false)
                    result.success(emptyMap<String, Any?>())
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Never let an exception escape into the engine: report it to Dart instead.
            Log.e(TAG, "Failed to handle ${call.method}", e)
            result.error(ERROR_CODE, e.message ?: e.toString(), null)
        }
    }

    private fun init(call: MethodCall, result: Result) {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error(ERROR_INVALID_ARGUMENT, "Missing player id", null)
            return
        }
        if (players.containsKey(id)) {
            result.error(ERROR_CODE, "Platform player $id already exists", null)
            return
        }
        players[id] = AudioPlayer(
            applicationContext,
            messenger,
            id,
            call.argument<Map<*, *>>("audioLoadConfiguration"),
            call.argument<List<Any?>>("androidAudioEffects") ?: emptyList(),
            call.argument<Map<*, *>>("androidAudioOffloadPreferences"),
            call.argument<Boolean>("androidOffloadSchedulingEnabled"),
            call.argument<Boolean>("useLazyPreparation") ?: true,
            call.argument<Boolean>("handleInterruptions") ?: true,
        )
        result.success(null)
    }

    /**
     * Disposes every player. [calledFromDeinit] is true while the FlutterEngine is being destroyed or restarted,
     * when no message may be sent; explicit disposal from Dart passes false.
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

    private companion object {
        const val TAG = "MainMethodCallHandler"
        const val ERROR_CODE = "error"
        const val ERROR_INVALID_ARGUMENT = "invalid_argument"
    }
}
