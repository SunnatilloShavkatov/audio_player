package uz.plugin.audio_player

/** A request field is missing, null, or has the wrong type. The handler reports it as `invalid_argument`. */
internal class InvalidArgumentException(val key: String) :
    IllegalArgumentException("Missing or invalid argument \"$key\"")

// Typed reads of a decoded request. Each one checks the field where it is read, so no caller needs an unchecked
// cast or a `!!`. JSON integers arrive as Int or Long, so the number readers accept both.

internal fun Map<*, *>.requireInt(key: String): Int = get(key) as? Int ?: throw InvalidArgumentException(key)

internal fun Map<*, *>.requireLong(key: String): Long = when (val value = get(key)) {
    is Long -> value
    is Int -> value.toLong()
    else -> throw InvalidArgumentException(key)
}

internal fun Map<*, *>.requireDouble(key: String): Double =
    (get(key) as? Number)?.toDouble() ?: throw InvalidArgumentException(key)

internal fun Map<*, *>.requireBool(key: String): Boolean = get(key) as? Boolean ?: throw InvalidArgumentException(key)

internal fun Map<*, *>.requireString(key: String): String = get(key) as? String ?: throw InvalidArgumentException(key)

internal fun Map<*, *>.requireMap(key: String): Map<*, *> = get(key) as? Map<*, *> ?: throw InvalidArgumentException(key)

internal fun Map<*, *>.requireIntList(key: String): List<Int> {
    val list = get(key) as? List<*> ?: throw InvalidArgumentException(key)
    return list.map { it as? Int ?: throw InvalidArgumentException(key) }
}

/** A long field that may be absent or null; a present field must still have the right type. */
internal fun Map<*, *>.optionalLong(key: String): Long? = if (get(key) == null) null else requireLong(key)

/** A field that may be absent or null; a present field must still be a [T]. */
internal inline fun <reified T : Any> Map<*, *>.optional(key: String): T? {
    val value = get(key) ?: return null
    return value as? T ?: throw InvalidArgumentException(key)
}
