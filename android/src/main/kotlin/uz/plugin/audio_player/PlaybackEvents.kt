package uz.plugin.audio_player

import androidx.media3.common.C

// Position bookkeeping, playback events sent to Dart and the replies to pending prepare and seek calls.

internal fun AudioPlayer.updatePositionIfChanged(): Boolean {
    val player = exoPlayer ?: return false
    if (!player.playWhenReady || processingState != ProcessingState.ready) {
        if (currentPositionMs() == updatePosition) return false
    }
    updatePosition = currentPositionMs()
    updateTime = System.currentTimeMillis()
    return true
}

internal fun AudioPlayer.updatePositionNow() {
    updatePosition = currentPositionMs()
    updateTime = System.currentTimeMillis()
}

internal fun AudioPlayer.updateCurrentIndex(): Boolean {
    val newIndex = player.currentMediaItemIndex
    // newIndex is never null.
    // currentIndex is sometimes null.
    if (newIndex != currentIndex) {
        currentIndex = newIndex
        return true
    }
    return false
}

private fun AudioPlayer.currentPositionMs(): Long {
    val sp = seekPos
    return if (processingState == ProcessingState.idle || processingState == ProcessingState.loading) {
        maxOf(player.currentPosition, 0L)
    } else if (sp != null && sp != C.TIME_UNSET) {
        sp
    } else {
        player.currentPosition
    }
}

private fun AudioPlayer.durationMs(): Long =
    if (processingState == ProcessingState.idle || processingState == ProcessingState.loading || exoPlayer == null) {
        C.TIME_UNSET
    } else {
        player.duration
    }

/** The duration in microseconds as expected by Dart, or null if unknown. */
internal fun AudioPlayer.durationMicros(): Long? {
    val duration = durationMs()
    return if (duration == C.TIME_UNSET) null else 1000 * duration
}

/** Creates an event based on the current state. */
private fun AudioPlayer.createPlaybackEvent(): Map<String, Any?> {
    bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
    return hashMapOf(
        "processingState" to processingState.ordinal,
        "updatePosition" to 1000 * updatePosition,
        "updateTime" to updateTime,
        "bufferedPosition" to 1000 * maxOf(updatePosition, bufferedPosition),
        "icyMetadata" to icyMetadata.toMap(),
        "duration" to durationMicros(),
        "currentIndex" to currentIndex,
        "androidAudioSessionId" to audioSessionId,
        "errorCode" to errorCode,
        "errorMessage" to errorMessage,
    )
}

// Broadcast the pending playback event if it was set.
internal fun AudioPlayer.broadcastPendingPlaybackEvent() {
    pendingPlaybackEvent?.let {
        events.playbackEvent(it)
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
internal fun AudioPlayer.enqueuePlaybackEvent() {
    pendingPlaybackEvent = createPlaybackEvent()
}

// Broadcasts a new event immediately.
internal fun AudioPlayer.broadcastImmediatePlaybackEvent() {
    enqueuePlaybackEvent()
    broadcastPendingPlaybackEvent()
}

/** Completes a pending [load] call with the duration, then applies any deferred audio attributes. */
internal fun AudioPlayer.completePrepare() {
    val result = prepareResult ?: return
    result.success(mapOf("duration" to durationMicros()))
    prepareResult = null
    pendingAudioAttributes?.let {
        player.setAudioAttributes(it, handlesAudioFocus(it))
        pendingAudioAttributes = null
    }
}

internal fun AudioPlayer.completeSeek() {
    seekPos = null
    seekResult?.success(emptyMap<String, Any?>())
    seekResult = null
}

internal fun AudioPlayer.abortSeek() {
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

internal fun AudioPlayer.sendError(errorCode: Int, errorMsg: String?, details: Any?, switchToIdle: Boolean = true) {
    // Forget the pending results before replying: a reply that throws must not leave them behind to be
    // answered a second time.
    val pendingPrepare = prepareResult
    prepareResult = null
    // A pending seek will never finish, so complete it, or Dart waits for it forever.
    abortSeek()
    events.playbackError(errorCode.toString(), errorMsg, details)
    this.errorCode = errorCode
    this.errorMessage = errorMsg
    if (switchToIdle) {
        processingState = ProcessingState.idle
    }
    broadcastImmediatePlaybackEvent()
    pendingPrepare?.error(errorCode.toString(), errorMsg, details)
}

internal fun AudioPlayer.abortExistingConnection(switchToIdle: Boolean) {
    sendError(AudioPlayer.ERROR_ABORT, "Connection aborted", null, switchToIdle)
}
