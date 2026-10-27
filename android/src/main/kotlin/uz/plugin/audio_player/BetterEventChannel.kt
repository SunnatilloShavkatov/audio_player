package uz.plugin.audio_player

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink

/** An [EventSink] that can be used before a listener attaches and after it detaches. */
class BetterEventChannel(messenger: BinaryMessenger, id: String) : EventSink {
    private val channel = EventChannel(messenger, id)
    private var eventSink: EventSink? = null

    init {
        channel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventSink?) {
                this@BetterEventChannel.eventSink = eventSink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun success(event: Any?) {
        eventSink?.success(event)
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        eventSink?.error(errorCode, errorMessage, errorDetails)
    }

    override fun endOfStream() {
        eventSink?.endOfStream()
    }

    /**
     * Ends the stream and unregisters the channel so the messenger stops referencing the handler.
     *
     * When [calledFromDeinit] is true the FlutterEngine is being destroyed, so nothing is sent and the handler is
     * left alone: the engine drops its handlers itself.
     */
    fun dispose(calledFromDeinit: Boolean) {
        val sink = eventSink
        eventSink = null
        if (calledFromDeinit) return
        sink?.endOfStream()
        channel.setStreamHandler(null)
    }
}
