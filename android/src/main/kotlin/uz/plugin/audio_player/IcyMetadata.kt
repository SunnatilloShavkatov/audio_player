package uz.plugin.audio_player

import androidx.media3.extractor.metadata.icy.IcyHeaders
import androidx.media3.extractor.metadata.icy.IcyInfo

/** The latest ICY info and headers of a stream, encoded for the playback events. */
internal class IcyMetadata {
    var info: IcyInfo? = null
        set(value) {
            field = value
            cachedMap = null
        }
    var headers: IcyHeaders? = null
        set(value) {
            field = value
            cachedMap = null
        }

    // Playback events are sent often but the ICY metadata rarely changes, so the
    // encoded map is built once and reused until the metadata changes.
    private var cachedMap: Map<String, Any?>? = null

    fun toMap(): Map<String, Any?> = cachedMap ?: encode().also { cachedMap = it }

    private fun encode(): Map<String, Any?> {
        val icyData = HashMap<String, Any?>()
        info?.let {
            icyData["info"] = hashMapOf("title" to it.title, "url" to it.url)
        }
        headers?.let {
            icyData["headers"] = hashMapOf(
                "bitrate" to it.bitrate,
                "genre" to it.genre,
                "name" to it.name,
                "metadataInterval" to it.metadataInterval,
                "url" to it.url,
                "isPublic" to it.isPublic,
            )
        }
        return icyData
    }
}
