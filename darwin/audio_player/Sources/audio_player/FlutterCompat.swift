import AVFoundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

extension FlutterPluginRegistrar {
    /// `messenger` is a method on iOS and a property on macOS.
    var binaryMessenger: FlutterBinaryMessenger {
        #if os(iOS)
        return messenger()
        #else
        return messenger
        #endif
    }
}
