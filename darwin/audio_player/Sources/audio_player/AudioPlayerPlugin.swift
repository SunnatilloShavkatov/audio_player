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
        registrar.publish(AudioPlayerPlugin(engineKey: key, scope: AudioPlayerApi.attach(engine: key)))
    }

    /// Engine teardown (app closed or Flutter engine destroyed): free this engine's native players only.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        AudioPlayerApi.detach(engine: engineKey, scope: scope)
    }
}
