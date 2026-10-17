import Foundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

final class BetterEventChannel: NSObject, FlutterStreamHandler {
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    init(name: String, messenger: FlutterBinaryMessenger) {
        eventChannel = FlutterEventChannel(name: name, binaryMessenger: messenger)
        super.init()
        eventChannel.setStreamHandler(self)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    func sendEvent(_ event: Any?) {
        eventSink?(event)
    }

    func dispose() {
        eventSink?(FlutterEndOfEventStream)
        eventChannel.setStreamHandler(nil)
    }
}
