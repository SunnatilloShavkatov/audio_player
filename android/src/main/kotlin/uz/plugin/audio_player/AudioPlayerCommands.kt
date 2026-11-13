@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package uz.plugin.audio_player

import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ShuffleOrder

// The playback commands that AudioPlayerMethodHandler runs on the player.

internal fun AudioPlayer.load(
    mediaSources: List<MediaSource>,
    shuffleOrder: ShuffleOrder,
    initialPosition: Long,
    initialIndex: Int?,
    result: PlayerResult,
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
    try {
        player.setMediaSources(mediaSources, initialIndex ?: 0, initialPosition)
        player.setShuffleOrder(shuffleOrder)
        player.prepare()
    } catch (e: RuntimeException) {
        // For example IllegalSeekPositionException for an initial index out of range. The caller replies with
        // the error, so forget the result and leave the loading state, or the next load would try to abort
        // a request that was already answered.
        prepareResult = null
        player.stop()
        processingState = ProcessingState.idle
        updatePositionNow()
        errorCode = null
        errorMessage = null
        enqueuePlaybackEvent()
        throw e
    }
}

internal fun AudioPlayer.play(result: PlayerResult) {
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

internal fun AudioPlayer.pause() {
    if (!player.playWhenReady) return
    player.playWhenReady = false
    updatePositionNow()
    enqueuePlaybackEvent()
    playResult?.let {
        it.success(emptyMap<String, Any?>())
        playResult = null
    }
}

internal fun AudioPlayer.setSpeed(speed: Float) {
    val params = player.playbackParameters
    if (params.speed == speed) return
    player.playbackParameters = PlaybackParameters(speed, params.pitch)
    if (player.playWhenReady) updatePositionNow()
    enqueuePlaybackEvent()
}

internal fun AudioPlayer.setPitch(pitch: Float) {
    val params = player.playbackParameters
    if (params.pitch == pitch) return
    player.playbackParameters = PlaybackParameters(params.speed, pitch)
    enqueuePlaybackEvent()
}

internal fun AudioPlayer.seek(position: Long, index: Int?, result: PlayerResult) {
    if (processingState == ProcessingState.idle || processingState == ProcessingState.loading) {
        result.success(emptyMap<String, Any?>())
        return
    }
    val targetIndex = index ?: player.currentMediaItemIndex
    // ExoPlayer silently ignores an index outside the playlist, so the seek would never finish.
    if (targetIndex < 0 || targetIndex >= player.mediaItemCount) {
        throw IllegalArgumentException("Invalid index $targetIndex for a playlist of ${player.mediaItemCount} items")
    }
    abortSeek()
    seekPos = position
    seekResult = result
    try {
        player.seekTo(targetIndex, position)
    } catch (e: RuntimeException) {
        seekResult = null
        seekPos = null
        throw e
    }
}

internal fun AudioPlayer.setAudioAttributes(contentType: Int, flags: Int, usage: Int) {
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
        player.setAudioAttributes(audioAttributes, handlesAudioFocus(audioAttributes))
    }
}

/**
 * Media3 handles the audio focus only for media and game usages, and fails the player with an
 * IllegalArgumentException for any other usage. Players with another usage play without asking for the focus.
 */
internal fun AudioPlayer.handlesAudioFocus(audioAttributes: AudioAttributes): Boolean =
    handleInterruptions && when (audioAttributes.usage) {
        C.USAGE_MEDIA, C.USAGE_GAME, C.USAGE_UNKNOWN -> true
        else -> false
    }
