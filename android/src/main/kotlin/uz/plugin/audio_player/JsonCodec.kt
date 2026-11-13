package uz.plugin.audio_player

import org.json.JSONArray
import org.json.JSONObject

/**
 * The JSON form of the messages exchanged with Dart: maps, lists, numbers, booleans, strings and null. Integers
 * decode as [Int] or [Long] by size, other numbers as [Double], like the standard message codec did.
 */
internal object JsonCodec {

    /** Decodes a JSON object; an empty or null [json] is an empty map. */
    fun decodeMap(json: String?): Map<String, Any?> =
        if (json.isNullOrEmpty()) emptyMap() else toMap(JSONObject(json))

    /** Encodes [value]; NaN and infinite numbers become null, as JSON has no form for them. */
    fun encode(value: Any?): String = toJson(value).toString()

    /** The text of an error's details: JSON for maps and lists, else the plain text; null stays null. */
    fun encodeDetails(details: Any?): String? = when (details) {
        null -> null
        is Map<*, *>, is Iterable<*> -> encode(details)
        else -> details.toString()
    }

    private fun toMap(obj: JSONObject): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = fromJson(obj.get(key))
        }
        return map
    }

    private fun fromJson(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> toMap(value)
        is JSONArray -> List(value.length()) { fromJson(value.get(it)) }
        else -> value
    }

    private fun toJson(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> JSONObject().also { obj ->
            for ((key, entry) in value) obj.put(key.toString(), toJson(entry))
        }
        is Iterable<*> -> JSONArray().also { array -> for (entry in value) array.put(toJson(entry)) }
        is IntArray -> JSONArray().also { array -> for (entry in value) array.put(entry) }
        is Double -> if (value.isNaN() || value.isInfinite()) JSONObject.NULL else value
        is Float -> if (value.isNaN() || value.isInfinite()) JSONObject.NULL else value.toDouble()
        is Number, is Boolean, is String -> value
        else -> value.toString()
    }
}
