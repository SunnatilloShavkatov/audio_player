package uz.plugin.audio_player

/** The error codes Dart receives. Dart maps them onto its exceptions, so they are stable. */
internal object ErrorCode {
    const val GENERIC = "error"
    const val ILLEGAL_STATE = "illegal_state"
    const val INVALID_ARGUMENT = "invalid_argument"
    const val UNIMPLEMENTED = "unimplemented"
    const val DETACHED = "detached"
}
