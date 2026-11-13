@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package uz.plugin.audio_player

import androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences
import androidx.media3.exoplayer.DefaultLivePlaybackSpeedControl
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LivePlaybackSpeedControl
import androidx.media3.exoplayer.LoadControl

// Decoding of the configuration passed to `init`, and of the arguments in the method calls.

/** Builds the offload preferences from the `androidAudioOffloadPreferences` map, or from the legacy flag. */
internal fun buildAudioOffloadPreferences(map: Map<*, *>?, offloadEnabled: Boolean): AudioOffloadPreferences {
    if (map != null) {
        return AudioOffloadPreferences.Builder()
            .setIsGaplessSupportRequired(map["isGaplessSupportRequired"] as Boolean)
            .setIsSpeedChangeSupportRequired(map["isSpeedChangeSupportRequired"] as Boolean)
            .setAudioOffloadMode(map["audioOffloadMode"] as Int)
            .build()
    }
    val offloadMode = if (offloadEnabled) {
        AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED
    } else {
        AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_DISABLED
    }
    return AudioOffloadPreferences.Builder()
        .setIsGaplessSupportRequired(!offloadEnabled)
        .setIsSpeedChangeSupportRequired(!offloadEnabled)
        .setAudioOffloadMode(offloadMode)
        .build()
}

/** Builds the load control from `audioLoadConfiguration.androidLoadControl`, or null to use the default one. */
internal fun buildLoadControl(audioLoadConfiguration: Map<*, *>?): LoadControl? {
    val loadControlMap = audioLoadConfiguration?.get("androidLoadControl") as Map<*, *>? ?: return null
    val builder = DefaultLoadControl.Builder()
        .setBufferDurationsMs(
            (getLong(loadControlMap["minBufferDuration"])!! / 1000).toInt(),
            (getLong(loadControlMap["maxBufferDuration"])!! / 1000).toInt(),
            (getLong(loadControlMap["bufferForPlaybackDuration"])!! / 1000).toInt(),
            (getLong(loadControlMap["bufferForPlaybackAfterRebufferDuration"])!! / 1000).toInt(),
        )
        .setPrioritizeTimeOverSizeThresholds(loadControlMap["prioritizeTimeOverSizeThresholds"] as Boolean)
        .setBackBuffer((getLong(loadControlMap["backBufferDuration"])!! / 1000).toInt(), false)
    (loadControlMap["targetBufferBytes"] as Int?)?.let { builder.setTargetBufferBytes(it) }
    return builder.build()
}

/**
 * Builds the live speed control from `audioLoadConfiguration.androidLivePlaybackSpeedControl`, or null to use the
 * default one.
 */
internal fun buildLivePlaybackSpeedControl(audioLoadConfiguration: Map<*, *>?): LivePlaybackSpeedControl? {
    val liveMap = audioLoadConfiguration?.get("androidLivePlaybackSpeedControl") as Map<*, *>? ?: return null
    return DefaultLivePlaybackSpeedControl.Builder()
        .setFallbackMinPlaybackSpeed((liveMap["fallbackMinPlaybackSpeed"] as Double).toFloat())
        .setFallbackMaxPlaybackSpeed((liveMap["fallbackMaxPlaybackSpeed"] as Double).toFloat())
        .setMinUpdateIntervalMs(getLong(liveMap["minUpdateInterval"])!! / 1000)
        .setProportionalControlFactor((liveMap["proportionalControlFactor"] as Double).toFloat())
        .setMaxLiveOffsetErrorMsForUnitSpeed(getLong(liveMap["maxLiveOffsetErrorForUnitSpeed"])!! / 1000)
        .setTargetLiveOffsetIncrementOnRebufferMs(getLong(liveMap["targetLiveOffsetIncrementOnRebuffer"])!! / 1000)
        .setMinPossibleLiveOffsetSmoothingFactor((liveMap["minPossibleLiveOffsetSmoothingFactor"] as Double).toFloat())
        .build()
}

// Dart can't distinguish between int sizes so
// Flutter may send us a Long or an Integer
// depending on the number of bits required to
// represent it.
internal fun getLong(o: Any?): Long? = when (o) {
    null -> null
    is Long -> o
    else -> (o as Int).toLong()
}

@Suppress("UNCHECKED_CAST")
internal fun <T> mapGet(o: Any?, key: String): T? = (o as? Map<*, *>)?.get(key) as T?

internal fun castToStringMap(map: Map<*, *>?): MutableMap<String, String>? =
    map?.entries?.associateTo(HashMap()) { it.key as String to it.value as String }
