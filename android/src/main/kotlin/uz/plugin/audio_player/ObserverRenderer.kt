@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package uz.plugin.audio_player

import android.os.Handler
import androidx.media3.exoplayer.NoSampleRenderer

/**
 * A renderer that only watches the playback position. When the position moves again after standing still for a few
 * render calls (playback resumed after a stall), it posts [onPositionResumed] to [handler].
 */
internal class ObserverRenderer(
    private val handler: Handler,
    private val onPositionResumed: () -> Unit,
) : NoSampleRenderer() {
    private var lastPosUs = 0L
    private var consecutivePosCount = 0

    override fun render(positionUs: Long, elapsedRealtimeUs: Long) {
        if (positionUs == lastPosUs) {
            consecutivePosCount++
        } else {
            if (consecutivePosCount >= 3) {
                handler.post { onPositionResumed() }
            }
            consecutivePosCount = 0
        }
        lastPosUs = positionUs
    }

    override fun getName(): String = "ObserverRenderer"
}
