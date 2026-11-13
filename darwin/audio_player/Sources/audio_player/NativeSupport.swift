import Foundation

/// Answers a call from Dart: a reply value (a map), or a `NativeError`.
typealias NativeResult = (Any?) -> Void

/// A failure reported to Dart: becomes a `PlatformException` there.
final class NativeError {
    let code: String
    let message: String?
    let details: Any?

    init(code: String, message: String?, details: Any?) {
        self.code = code
        self.message = message
        self.details = details
    }
}

/// What one player reports to Dart: the playback events or the data updates, depending on `kind`.
/// Once disposed it delivers nothing, so a late callback never reaches Dart.
final class PlayerEventSink {
    enum Kind {
        case playback
        case data
    }

    private let kind: Kind
    private let playerId: String
    private var closed = false

    init(kind: Kind, playerId: String) {
        self.kind = kind
        self.playerId = playerId
    }

    /// Sends an event map, or a `NativeError` as an error on the playback event stream.
    func sendEvent(_ event: Any?) {
        guard !closed else { return }
        AudioPlayerApi.deliver(kind, playerId: playerId, event: event)
    }

    /// Stops all delivery. Nothing is sent, so this is safe while the engine is going away
    /// (`calledFromDeinit`): the Dart side is gone and its listener blocks must not be called.
    func dispose(calledFromDeinit: Bool) {
        closed = true
    }
}
