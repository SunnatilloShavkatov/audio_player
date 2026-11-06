package uz.plugin.audio_player

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Util
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.ClippingMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.SilenceMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory

/**
 * Decodes the `AudioSource` messages from Dart into ExoPlayer media sources, and keeps them by id so a source that
 * Dart sends again (for example in a later playlist) is reused.
 */
internal class AudioSourceDecoder(private val context: Context) {
    private val mediaSources = HashMap<String, MediaSource>()

    // Shared by every source that does not customise its headers or extractor
    // options, so large playlists do not allocate one factory per item.
    private val defaultDataSourceFactory: DataSource.Factory by lazy { createDataSourceFactory(null) }
    private val defaultExtractorsFactory: DefaultExtractorsFactory by lazy { createExtractorsFactory(null) }

    fun getAudioSources(json: Any?): List<MediaSource> {
        if (json !is List<*>) throw RuntimeException("List expected: $json")
        return json.map { getAudioSource(it) }
    }

    /** Forgets the sources that the source tree [json] no longer uses. */
    fun retainUsedBy(json: Any?) {
        val usedIds = HashSet<String>()
        collectAudioSourceIds(json, usedIds)
        mediaSources.keys.retainAll(usedIds)
    }

    fun clear() {
        mediaSources.clear()
    }

    private fun getAudioSource(json: Any?): MediaSource {
        val map = json as Map<*, *>
        val id = map["id"] as String
        return mediaSources.getOrPut(id) { decodeAudioSource(map) }
    }

    private fun collectAudioSourceIds(json: Any?, ids: MutableSet<String>) {
        val map = json as? Map<*, *> ?: return
        (map["id"] as? String)?.let { ids.add(it) }
        (map["children"] as? List<*>)?.forEach { collectAudioSourceIds(it, ids) }
        collectAudioSourceIds(map["child"], ids)
    }

    private fun decodeAudioSource(map: Map<*, *>): MediaSource {
        val id = map["id"] as String
        return when (val type = map["type"] as String) {
            "progressive" -> ProgressiveMediaSource.Factory(
                buildDataSourceFactory(mapGet(map, "headers")),
                buildExtractorsFactory(mapGet(map, "options")),
            ).createMediaSource(
                MediaItem.Builder()
                    .setUri(Uri.parse(map["uri"] as String))
                    .setTag(id)
                    .build(),
            )
            "dash" -> DashMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                .createMediaSource(
                    MediaItem.Builder()
                        .setUri(Uri.parse(map["uri"] as String))
                        .setMimeType(MimeTypes.APPLICATION_MPD)
                        .setTag(id)
                        .build(),
                )
            "hls" -> HlsMediaSource.Factory(buildDataSourceFactory(mapGet(map, "headers")))
                .createMediaSource(
                    MediaItem.Builder()
                        .setUri(Uri.parse(map["uri"] as String))
                        .setMimeType(MimeTypes.APPLICATION_M3U8)
                        .build(),
                )
            "silence" -> SilenceMediaSource.Factory()
                .setDurationUs(getLong(map["duration"])!!)
                .setTag(id)
                .createMediaSource()
            "clipping" -> ClippingMediaSource.Builder(getAudioSource(map["child"]))
                .setStartPositionUs(getLong(map["start"]) ?: 0L)
                .setEndPositionUs(getLong(map["end"]) ?: C.TIME_END_OF_SOURCE)
                .build()
            else -> throw IllegalArgumentException("Unknown AudioSource type: $type")
        }
    }

    private fun buildExtractorsFactory(options: Map<*, *>?): DefaultExtractorsFactory =
        if (options?.get("androidExtractorOptions") == null) defaultExtractorsFactory else createExtractorsFactory(options)

    private fun createExtractorsFactory(options: Map<*, *>?): DefaultExtractorsFactory {
        var constantBitrateSeekingEnabled = true
        var constantBitrateSeekingAlwaysEnabled = false
        var mp3Flags = 0
        val androidExtractorOptions = options?.get("androidExtractorOptions") as Map<*, *>?
        if (androidExtractorOptions != null) {
            constantBitrateSeekingEnabled = androidExtractorOptions["constantBitrateSeekingEnabled"] as Boolean
            constantBitrateSeekingAlwaysEnabled = androidExtractorOptions["constantBitrateSeekingAlwaysEnabled"] as Boolean
            mp3Flags = androidExtractorOptions["mp3Flags"] as Int
        }
        return DefaultExtractorsFactory().apply {
            setConstantBitrateSeekingEnabled(constantBitrateSeekingEnabled)
            setConstantBitrateSeekingAlwaysEnabled(constantBitrateSeekingAlwaysEnabled)
            setMp3ExtractorFlags(mp3Flags)
        }
    }

    private fun buildDataSourceFactory(headers: Map<*, *>?): DataSource.Factory =
        if (headers.isNullOrEmpty()) defaultDataSourceFactory else createDataSourceFactory(headers)

    private fun createDataSourceFactory(headers: Map<*, *>?): DataSource.Factory {
        val stringHeaders = castToStringMap(headers)
        var userAgent: String? = null
        if (stringHeaders != null) {
            userAgent = stringHeaders.remove("User-Agent") ?: stringHeaders.remove("user-agent")
        }
        if (userAgent == null) {
            userAgent = Util.getUserAgent(context, "audio_player")
        }
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
        if (!stringHeaders.isNullOrEmpty()) {
            httpDataSourceFactory.setDefaultRequestProperties(stringHeaders)
        }
        return DefaultDataSource.Factory(context, httpDataSourceFactory)
    }
}
