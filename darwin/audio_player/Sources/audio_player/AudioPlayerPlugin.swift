#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

public class AudioPlayerPlugin: NSObject, FlutterPlugin {
    private let registrar: FlutterPluginRegistrar
    private var players: [String: AudioPlayer] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "uz.plugin.audio_player.methods", binaryMessenger: registrar.binaryMessenger)
        let instance = AudioPlayerPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let request = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "init":
            guard let playerId = request["id"] as? String else {
                result(FlutterError(code: "error", message: "Missing player id", details: nil))
                return
            }
            if players[playerId] != nil {
                result(FlutterError(code: "error", message: "Platform player already exists", details: nil))
            } else {
                let loadConfiguration = request["audioLoadConfiguration"] as? [String: Any]
                players[playerId] = AudioPlayer(
                    registrar: registrar,
                    playerId: playerId,
                    loadConfiguration: loadConfiguration,
                    handleInterruptions: request["handleInterruptions"] as? Bool ?? true,
                    handleAudioSessionActivation: request["handleAudioSessionActivation"] as? Bool ?? true
                )
                result(nil)
            }
        case "disposePlayer":
            if let playerId = request["id"] as? String {
                players.removeValue(forKey: playerId)?.dispose(calledFromDeinit: false)
            }
            result([String: Any]())
        case "disposeAllPlayers":
            for player in players.values {
                player.dispose(calledFromDeinit: false)
            }
            players.removeAll()
            result([String: Any]())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    deinit {
        for player in players.values {
            player.dispose(calledFromDeinit: true)
        }
    }
}
