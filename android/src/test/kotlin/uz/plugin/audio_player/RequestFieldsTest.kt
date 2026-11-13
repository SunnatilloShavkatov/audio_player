package uz.plugin.audio_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class RequestFieldsTest {
    private val request: Map<String, Any?> = mapOf(
        "index" to 2,
        "position" to 1500L,
        "volume" to 0.5,
        "enabled" to true,
        "type" to "bass",
        "shuffleOrder" to listOf(1, 0),
        "audioSource" to mapOf("children" to emptyList<Any>()),
        "missing" to null,
    )

    @Test
    fun readsEachTypedField() {
        assertEquals(2, request.requireInt("index"))
        assertEquals(1500L, request.requireLong("position"))
        assertEquals(0.5, request.requireDouble("volume"), 0.0)
        assertEquals(true, request.requireBool("enabled"))
        assertEquals("bass", request.requireString("type"))
        assertEquals(listOf(1, 0), request.requireIntList("shuffleOrder"))
        assertEquals(mapOf("children" to emptyList<Any>()), request.requireMap("audioSource"))
    }

    @Test
    fun integersAreAcceptedWhereLongsAndDoublesAreWanted() {
        assertEquals(2L, request.requireLong("index"))
        assertEquals(2.0, request.requireDouble("index"), 0.0)
    }

    @Test
    fun absentOrNullFieldIsInvalidArgument() {
        val missing = assertThrows(InvalidArgumentException::class.java) { request.requireInt("absent") }
        assertEquals("absent", missing.key)
        assertThrows(InvalidArgumentException::class.java) { request.requireInt("missing") }
    }

    @Test
    fun wrongTypeIsInvalidArgument() {
        assertThrows(InvalidArgumentException::class.java) { request.requireInt("type") }
        assertThrows(InvalidArgumentException::class.java) { request.requireBool("index") }
        assertThrows(InvalidArgumentException::class.java) { request.requireString("index") }
        assertThrows(InvalidArgumentException::class.java) { request.requireMap("shuffleOrder") }
        assertThrows(InvalidArgumentException::class.java) { request.requireIntList("volume") }
    }

    @Test
    fun listWithAWrongElementIsInvalidArgument() {
        val mixed = mapOf("shuffleOrder" to listOf(1, "x"))
        assertThrows(InvalidArgumentException::class.java) { mixed.requireIntList("shuffleOrder") }
    }

    @Test
    fun optionalFieldsAreNullOnlyWhenAbsent() {
        assertNull(request.optionalLong("absent"))
        assertNull(request.optionalLong("missing"))
        assertEquals(1500L, request.optionalLong("position"))
        assertThrows(InvalidArgumentException::class.java) { request.optionalLong("type") }
    }
}
