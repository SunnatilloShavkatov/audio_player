package uz.plugin.audio_player

import androidx.media3.common.Metadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.extractor.metadata.icy.IcyHeaders
import androidx.media3.extractor.metadata.icy.IcyInfo
import io.flutter.Log

/** Turns ExoPlayer's callbacks into state changes of [audioPlayer] and events for Dart. */
internal class PlayerEventListener(private val audioPlayer: AudioPlayer) : Player.Listener {

    override fun onIsLoadingChanged(isLoading: Boolean) {
        // Starting reads the buffer position again; stopping takes a final reading.
        audioPlayer.startWatchingBuffer()
    }

    /**
     * While ExoPlayer is ready and `playWhenReady` is set but playback is suppressed (for example during a short
     * audio focus loss) `isPlaying` is false and the position stands still, yet no other callback fires. Take a fresh
     * position reading whenever that changes so Dart's position estimate does not run ahead. Other changes of
     * `isPlaying` come with a change of `playWhenReady` or of the playback state, which report on their own.
     */
    override fun onIsPlayingChanged(isPlaying: Boolean) {
        with(audioPlayer) {
            if (exoPlayer?.playWhenReady != true || processingState != ProcessingState.ready) return
            updatePositionNow()
            broadcastImmediatePlaybackEvent()
        }
    }

    override fun onAudioSessionIdChanged(audioSessionId: Int) {
        audioPlayer.updateAudioSessionId(audioSessionId)
        audioPlayer.broadcastPendingPlaybackEvent()
    }

    override fun onMetadata(metadata: Metadata) {
        for (i in 0 until metadata.length()) {
            val entry = metadata[i]
            if (entry is IcyInfo) {
                audioPlayer.icyMetadata.info = entry
                audioPlayer.broadcastImmediatePlaybackEvent()
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
                        audioPlayer.icyMetadata.headers = entry
                        audioPlayer.broadcastImmediatePlaybackEvent()
                    }
                }
            }
        }
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        with(audioPlayer) {
            updatePositionNow()
            when (reason) {
                Player.DISCONTINUITY_REASON_AUTO_TRANSITION,
                Player.DISCONTINUITY_REASON_SEEK -> updateCurrentIndex()
            }
            broadcastImmediatePlaybackEvent()
        }
    }

    override fun onTimelineChanged(timeline: Timeline, reason: Int) {
        with(audioPlayer) {
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
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        with(audioPlayer) {
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
                    // A seek to the end of the last item (loop off) ends playback instead of becoming ready.
                    if (seekResult != null) {
                        completeSeek()
                    }
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
                // STATE_IDLE: nothing to report.
                else -> {}
            }
        }
    }

    /**
     * ExoPlayer pauses itself when the audio focus is lost for good, when headphones are unplugged and when
     * playback stayed suppressed for too long. Dart owns the `playing` state, so it has to be told.
     */
    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        with(audioPlayer) {
            if (playWhenReady || reason == Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST) return
            updatePositionNow()
            enqueuePlaybackEvent()
            playResult?.let {
                it.success(emptyMap<String, Any?>())
                playResult = null
            }
            events.playerData(mapOf("playing" to false))
            broadcastPendingPlaybackEvent()
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        val message = buildString {
            append(error.message ?: "Playback error")
            append(" [${error.errorCodeName} (${error.errorCode})]")
            // Dart reporters cannot read Logcat, so preserve the native cause chain in the message.
            generateSequence(error.cause) { it.cause }.take(8).forEach { cause ->
                append(" <- ${cause.javaClass.name}: ${cause.message.orEmpty().take(512)}")
            }
        }
        Log.e(AudioPlayer.TAG, message, error)
        // Keep the public numeric code compatible with existing PlayerException handlers.
        val code = if (error is ExoPlaybackException) error.type else error.errorCode
        audioPlayer.sendError(code, message, mapOf("index" to audioPlayer.currentIndex))
    }
}
