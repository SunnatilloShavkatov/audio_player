@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package uz.plugin.audio_player

import androidx.media3.common.C
import androidx.media3.exoplayer.source.ShuffleOrder
import androidx.media3.exoplayer.source.ShuffleOrder.DefaultShuffleOrder
import io.flutter.Log
import java.util.Random


private val random = Random()

/** Decodes the calls Dart makes on a player and runs them on [audioPlayer]. */
internal class AudioPlayerMethodHandler(private val audioPlayer: AudioPlayer) {

    fun onCall(call: PlayerCall, result: PlayerResult) {
        audioPlayer.handle(call, result)
    }

    private fun AudioPlayer.handle(call: PlayerCall, result: PlayerResult) {
        try {
            // Inside the try so a failure is reported to Dart and retried on the next call.
            ensurePlayerInitialized()
            when (call.method) {
                "load" -> {
                    val initialPosition = call.arguments.optionalLong("initialPosition")
                    val initialIndex = call.arguments.optional<Int>("initialIndex")
                    val audioSourceMap = call.arguments.requireMap("audioSource")
                    val children = audioSources.getAudioSources(audioSourceMap["children"])
                    // Forget sources from earlier playlists that this one no longer uses.
                    audioSources.retainUsedBy(audioSourceMap)
                    val shuffleOrder = decodeShuffleOrder(audioSourceMap.requireIntList("shuffleOrder"))
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
                    player.volume = call.arguments.requireDouble("volume").toFloat()
                    result.success(emptyMap<String, Any?>())
                }
                "setSpeed" -> {
                    setSpeed(call.arguments.requireDouble("speed").toFloat())
                    result.success(emptyMap<String, Any?>())
                }
                "setPitch" -> {
                    setPitch(call.arguments.requireDouble("pitch").toFloat())
                    result.success(emptyMap<String, Any?>())
                }
                "setSkipSilence" -> {
                    player.setSkipSilenceEnabled(call.arguments.requireBool("enabled"))
                    result.success(emptyMap<String, Any?>())
                }
                "setLoopMode" -> {
                    player.repeatMode = call.arguments.requireInt("loopMode")
                    result.success(emptyMap<String, Any?>())
                }
                "setShuffleMode" -> {
                    player.setShuffleModeEnabled(call.arguments.optional<Int>("shuffleMode") == 1)
                    result.success(emptyMap<String, Any?>())
                }
                "setShuffleOrder" -> {
                    val playlist = call.arguments.requireMap("audioSource")
                    player.setShuffleOrder(decodeShuffleOrder(playlist.requireIntList("shuffleOrder")))
                    result.success(emptyMap<String, Any?>())
                }
                "setAutomaticallyWaitsToMinimizeStalling",
                "setAllowsExternalPlayback",
                "setCanUseNetworkResourcesForLiveStreamingWhilePaused",
                "setPreferredPeakBitRate" -> result.success(emptyMap<String, Any?>())
                "seek" -> {
                    val position = call.arguments.optionalLong("position")
                    val index = call.arguments.optional<Int>("index")
                    seek(if (position == null) C.TIME_UNSET else position / 1000, index, result)
                }
                // The playlist is always the root one, which maps onto ExoPlayer's
                // own playlist.
                "concatenatingInsertAll" -> {
                    val index = call.arguments.requireInt("index")
                    val children = audioSources.getAudioSources(call.arguments["children"])
                    player.addMediaSources(index, children)
                    player.setShuffleOrder(decodeShuffleOrder(call.arguments.requireIntList("shuffleOrder")))
                    result.success(emptyMap<String, Any?>())
                }
                "concatenatingRemoveRange" -> {
                    player.removeMediaItems(call.arguments.requireInt("startIndex"), call.arguments.requireInt("endIndex"))
                    player.setShuffleOrder(decodeShuffleOrder(call.arguments.requireIntList("shuffleOrder")))
                    result.success(emptyMap<String, Any?>())
                }
                "concatenatingMove" -> {
                    player.moveMediaItem(call.arguments.requireInt("currentIndex"), call.arguments.requireInt("newIndex"))
                    player.setShuffleOrder(decodeShuffleOrder(call.arguments.requireIntList("shuffleOrder")))
                    result.success(emptyMap<String, Any?>())
                }
                "setAndroidAudioAttributes" -> {
                    setAudioAttributes(
                        call.arguments.requireInt("contentType"),
                        call.arguments.requireInt("flags"),
                        call.arguments.requireInt("usage"),
                    )
                    result.success(emptyMap<String, Any?>())
                }
                "audioEffectSetEnabled" -> {
                    audioEffects.setEnabled(call.arguments.requireString("type"), call.arguments.requireBool("enabled"))
                    result.success(emptyMap<String, Any?>())
                }
                "androidLoudnessEnhancerSetTargetGain" -> {
                    val targetGain = call.arguments.optional<Number>("targetGain")?.toDouble() ?: 0.0
                    audioEffects.loudnessEnhancerSetTargetGain(targetGain)
                    result.success(emptyMap<String, Any?>())
                }
                "androidEqualizerGetParameters" -> result.success(audioEffects.equalizerGetParameters())
                "androidEqualizerBandSetGain" -> {
                    val gain = call.arguments.optional<Number>("gain")?.toDouble() ?: 0.0
                    audioEffects.equalizerBandSetGain(call.arguments.requireInt("bandIndex"), gain)
                    result.success(emptyMap<String, Any?>())
                }
                else -> result.error(ErrorCode.UNIMPLEMENTED, "Unknown method ${call.method}", null)
            }
        } catch (e: InvalidArgumentException) {
            result.error(ErrorCode.INVALID_ARGUMENT, e.message, null)
        } catch (e: IllegalStateException) {
            Log.e(AudioPlayer.TAG, "Illegal state in ${call.method}", e)
            result.error(ErrorCode.ILLEGAL_STATE, e.message ?: e.toString(), e.toString())
        } catch (e: Exception) {
            Log.e(AudioPlayer.TAG, "Error in ${call.method}", e)
            result.error(ErrorCode.GENERIC, e.message ?: e.toString(), e.toString())
        } finally {
            broadcastPendingPlaybackEvent()
        }
    }

    private fun decodeShuffleOrder(indexList: List<Int>): ShuffleOrder =
        DefaultShuffleOrder(indexList.toIntArray(), random.nextLong())
}
