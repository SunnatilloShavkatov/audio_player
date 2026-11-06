package uz.plugin.audio_player

import android.media.audiofx.AudioEffect
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import io.flutter.Log

/** Creates the audio effects requested by Dart for the player's audio session, and applies changes to them. */
internal class AudioEffectsController(private val rawAudioEffects: List<Any?>) {
    private val audioEffects = ArrayList<AudioEffect>()
    private val audioEffectsMap = HashMap<String, AudioEffect>()

    /** Releases the current effects and creates them again for [audioSessionId], if there is one. */
    fun attach(audioSessionId: Int?) {
        clear()
        audioSessionId ?: return
        for (rawAudioEffect in rawAudioEffects) {
            val json = rawAudioEffect as Map<*, *>
            // Some devices do not provide an effect (or refuse it for this session); skip it rather than
            // leaving the player half set up.
            val audioEffect = try {
                decodeAudioEffect(json, audioSessionId)
            } catch (e: RuntimeException) {
                Log.e(AudioPlayer.TAG, "Could not create audio effect ${json["type"]}", e)
                continue
            }
            if (json["enabled"] as Boolean) {
                audioEffect.setEnabled(true)
            }
            audioEffects.add(audioEffect)
            audioEffectsMap[json["type"] as String] = audioEffect
        }
    }

    fun clear() {
        audioEffects.forEach { it.release() }
        audioEffects.clear()
        audioEffectsMap.clear()
    }

    fun setEnabled(type: String, enabled: Boolean) {
        audioEffectsMap[type]?.setEnabled(enabled)
    }

    fun loudnessEnhancerSetTargetGain(targetGain: Double) {
        // target gain needs to be provided in milliBel, the user provides the value in deciBel
        val targetGainMillibels = Math.round(targetGain * 100.0).toInt()
        (audioEffectsMap["AndroidLoudnessEnhancer"] as? LoudnessEnhancer)?.setTargetGain(targetGainMillibels)
    }

    fun equalizerGetParameters(): Map<String, Any?> {
        val equalizer = audioEffectsMap["AndroidEqualizer"] as? Equalizer
            ?: return mapOf(
                "parameters" to mapOf(
                    "minDecibels" to 0.0,
                    "maxDecibels" to 0.0,
                    "bands" to emptyList<Map<String, Any?>>(),
                ),
            )
        val rawBands = ArrayList<Any?>()
        for (i in 0 until equalizer.numberOfBands.toInt()) {
            val band = i.toShort()
            val freqRange = equalizer.getBandFreqRange(band)
            // Frequencies are returned in milliHertz, we want Hertz.
            rawBands.add(
                mapOf(
                    "index" to i,
                    "lowerFrequency" to freqRange[0].toDouble() / 1000.0,
                    "upperFrequency" to freqRange[1].toDouble() / 1000.0,
                    "centerFrequency" to equalizer.getCenterFreq(band).toDouble() / 1000.0,
                    // returns a value in milliBel, we want deciBel
                    "gain" to equalizer.getBandLevel(band) / 100.0,
                ),
            )
        }
        val levelRange = equalizer.bandLevelRange
        return mapOf(
            "parameters" to mapOf(
                // returns a value in milliBel, we want deciBel
                "minDecibels" to levelRange[0] / 100.0,
                "maxDecibels" to levelRange[1] / 100.0,
                "bands" to rawBands,
            ),
        )
    }

    fun equalizerBandSetGain(bandIndex: Int, gain: Double) {
        // target gain needs to be provided in milliBel, the user provides the value in deciBel
        (audioEffectsMap["AndroidEqualizer"] as? Equalizer)
            ?.setBandLevel(bandIndex.toShort(), Math.round(gain * 100.0).toShort())
    }

    private fun decodeAudioEffect(map: Map<*, *>, audioSessionId: Int): AudioEffect =
        when (val type = map["type"] as String) {
            "AndroidLoudnessEnhancer" -> {
                // target gain needs to be provided in milliBel, the user provides the value in deciBel
                val rawGain = (map["targetGain"] as? Number)?.toDouble() ?: 0.0
                val targetGain = Math.round(rawGain * 100.0).toInt()
                LoudnessEnhancer(audioSessionId).apply { setTargetGain(targetGain) }
            }
            "AndroidEqualizer" -> Equalizer(0, audioSessionId)
            else -> throw IllegalArgumentException("Unknown AudioEffect type: $type")
        }
}
