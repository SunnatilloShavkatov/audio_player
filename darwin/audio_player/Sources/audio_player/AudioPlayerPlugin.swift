#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// Only the engine lifecycle: Dart calls `AudioPlayerApi` through the Objective-C runtime, so there is no method
/// channel on Apple platforms either.
public class AudioPlayerPlugin: NSObject, FlutterPlugin {
    private let engineKey: Int64
    private let scope: EngineScope

    private init(engineKey: Int64, scope: EngineScope) {
        self.engineKey = engineKey
        self.scope = scope
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Each engine registers its own instance and gets its own players. Publishing keeps this instance alive so
        // `detachFromEngine` runs. Dart looks `AudioPlayerApi` up by name, so this reference is also what keeps its
        // class out of the linker's dead-code stripping.
        let key = AudioPlayerApi.engineKey(of: registrar)
        let scope = AudioPlayerApi.attach(engine: key)
        registrar.publish(AudioPlayerPlugin(engineKey: key, scope: scope))
        #if os(macOS)
        // macOS never calls detachFromEngine. The messenger belongs to the engine and goes away with it, so a sentinel
        // tied to it frees the engine's players then. Nothing is sent: the scope detaches as from deinit.
        let sentinel = EngineLifetimeSentinel { AudioPlayerApi.detach(engine: key, scope: scope) }
        objc_setAssociatedObject(registrar.messenger, &engineLifetimeKey, sentinel, .OBJC_ASSOCIATION_RETAIN)
        #endif
    }

    /// Engine teardown (app closed or Flutter engine destroyed): free this engine's native players only.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        AudioPlayerApi.detach(engine: engineKey, scope: scope)
    }
}

#if os(macOS)
private var engineLifetimeKey: UInt8 = 0

/// Runs `onEnd` when the object it is attached to is deallocated.
private final class EngineLifetimeSentinel: NSObject {
    private let onEnd: () -> Void

    init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
    }

    deinit {
        onEnd()
    }
}
#endif
