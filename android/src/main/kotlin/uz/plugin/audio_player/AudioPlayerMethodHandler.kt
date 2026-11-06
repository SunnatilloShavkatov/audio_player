package uz.plugin.audio_player

import androidx.media3.common.C
import androidx.media3.exoplayer.source.ShuffleOrder
import androidx.media3.exoplayer.source.ShuffleOrder.DefaultShuffleOrder
import io.flutter.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.Random

// Stable, machine-readable codes for errors raised by method calls.
private const val ERROR_ILLEGAL_STATE = "illegal_state"
private const val ERROR_GENERIC = "error"

private val random = Random()

/** Decodes the calls on a player's method channel and runs them on [audioPlayer]. */
internal class AudioPlayerMethodHandler(private val audioPlayer: AudioPlayer) : MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: Result) {
        audioPlayer.handle(call, result)
    }

    private fun AudioPlayer.handle(call: MethodCall, result: Result) {
        try {
            // Inside the try so a failure is reported to Dart and retried on the next call.
            ensurePlayerInitialized()
            when (call.method) {
                "load" -> {
                    val initialPosition = getLong(call.argument<Any>("initialPosition"))
                    val initialIndex = call.argument<Int>("initialIndex")
                    val audioSourceMap = call.argument<Map<*, *>>("audioSource")!!
                    val children = audioSources.getAudioSources(audioSourceMap["children"])
                    // Forget sources from earlier playlists that this one no longer uses.
                    audioSources.retainUsedBy(audioSourceMap)
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
                "setAllowsExternalPlayback",
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
                    val children = audioSources.getAudioSources(call.argument<Any>("children"))
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
                    audioEffects.setEnabled(call.argument<String>("type")!!, call.argument<Boolean>("enabled")!!)
                    result.success(emptyMap<String, Any?>())
                }
                "androidLoudnessEnhancerSetTargetGain" -> {
                    val targetGain = call.argument<Number>("targetGain")?.toDouble() ?: 0.0
                    audioEffects.loudnessEnhancerSetTargetGain(targetGain)
                    result.success(emptyMap<String, Any?>())
                }
                "androidEqualizerGetParameters" -> result.success(audioEffects.equalizerGetParameters())
                "androidEqualizerBandSetGain" -> {
                    val gain = call.argument<Number>("gain")?.toDouble() ?: 0.0
                    audioEffects.equalizerBandSetGain(call.argument<Int>("bandIndex")!!, gain)
                    result.success(emptyMap<String, Any?>())
                }
                else -> result.notImplemented()
            }
        } catch (e: IllegalStateException) {
            Log.e(AudioPlayer.TAG, "Illegal state in ${call.method}", e)
            result.error(ERROR_ILLEGAL_STATE, e.message ?: e.toString(), e.toString())
        } catch (e: Exception) {
            Log.e(AudioPlayer.TAG, "Error in ${call.method}", e)
            result.error(ERROR_GENERIC, e.message ?: e.toString(), e.toString())
        } finally {
            broadcastPendingPlaybackEvent()
        }
    }

    private fun decodeShuffleOrder(indexList: List<Int>): ShuffleOrder =
        DefaultShuffleOrder(indexList.toIntArray(), random.nextLong())
}
