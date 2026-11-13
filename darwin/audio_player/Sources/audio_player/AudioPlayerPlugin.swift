#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// Only the engine lifecycle: Dart calls `AudioPlayerApi` through the Objective-C runtime, so there is no method
/// channel on Apple platforms either.
public class AudioPlayerPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Publishing keeps this instance alive so `detachFromEngine` runs. Dart looks `AudioPlayerApi` up by name,
        // so this reference is also what keeps its class out of the linker's dead-code stripping.
        _ = AudioPlayerApi.self
        registrar.publish(AudioPlayerPlugin())
    }

    /// Engine teardown (app closed or Flutter engine destroyed): free every native player.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        AudioPlayerApi.detach()
    }
}
