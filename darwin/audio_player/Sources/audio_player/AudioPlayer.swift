import AVFoundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

let errorAbort = 10_000_000

enum ProcessingState: Int {
    case idle
    case loading
    case buffering
    case ready
    case completed
}

enum LoopMode: Int {
    case off
    case one
    case all
}

enum PlayerError: Error {
    case invalidSource
    case unknownSourceType
    case invalidIndex
    case invalidArgument
}

/// One native player, driven over its own method channel.
///
/// The class holds the state; the behaviour lives in the `AudioPlayer+*.swift` extensions.
final class AudioPlayer: NSObject {
    let methodChannel: FlutterMethodChannel
    let eventChannel: BetterEventChannel
    let dataEventChannel: BetterEventChannel
    let playerId: String
    let loadControl: LoadControl
    let handleAudioSessionActivation: Bool

    var player: AVQueuePlayer?
    var speed: Float = 1.0

    var audioSource: AudioSource?
    var indexedAudioSources: [IndexedAudioSource] = []
    var order: [Int] = []
    var orderInv: [Int] = []
    var index = 0
    var processingState = ProcessingState.idle
    var loopMode = LoopMode.off
    var shuffleModeEnabled = false
    var updateTime = 0
    var updatePositionMs = 0
    var bufferedPosition = 0
    // Set when the current item hasn't been played yet so we aren't sure whether sufficient audio has been buffered.
    var bufferUnconfirmed = false
    var seekPos = CMTime.invalid
    var loadResult: FlutterResult?
    var playResult: FlutterResult?
    var automaticallyWaitsToMinimizeStalling = true
    var allowsExternalPlayback = false
    var playing = false
    var volume: Float = 1.0
    var justAdvanced = false
    var enqueuedAll = false
    var icyMetadata: [String: Any] = [:]
    var errorCode: Int?
    var errorMessage: String?
    // Items whose KVO and notification observers are currently registered.
    let observedItems = NSHashTable<AVPlayerItem>.weakObjects()
    // Per observed item (by identity): the end-of-item observer token and the ICY metadata output.
    var endObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    var metadataOutputs: [ObjectIdentifier: AVPlayerItemMetadataOutput] = [:]
    // Incremented for every seek (and load) so that the completion of a superseded one doesn't touch current state.
    var seekGeneration = 0
    // Set by dispose. Late callbacks must not touch state, and after `disposedFromDeinit` must not reply or send.
    var disposed = false
    var disposedFromDeinit = false
    // Set when an audio session interruption paused playback that should resume once the interruption ends.
    var resumeAfterInterruption = false
    var audioSessionObservers: [NSObjectProtocol] = []

    init(
        registrar: FlutterPluginRegistrar,
        playerId: String,
        loadConfiguration: [String: Any]?,
        handleInterruptions: Bool,
        handleAudioSessionActivation: Bool
    ) {
        self.playerId = playerId
        self.handleAudioSessionActivation = handleAudioSessionActivation
        let messenger = registrar.binaryMessenger
        methodChannel = FlutterMethodChannel(name: "uz.plugin.audio_player.methods.\(playerId)", binaryMessenger: messenger)
        eventChannel = BetterEventChannel(name: "uz.plugin.audio_player.events.\(playerId)", messenger: messenger)
        dataEventChannel = BetterEventChannel(name: "uz.plugin.audio_player.data.\(playerId)", messenger: messenger)

        loadControl = LoadControl()
        super.init()

        if let map = loadConfiguration?["darwinLoadControl"] as? [String: Any] {
            loadControl.preferredForwardBufferDuration = (map["preferredForwardBufferDuration"] as? NSNumber)?.int64Value
            loadControl.canUseNetworkResourcesForLiveStreamingWhilePaused = (map["canUseNetworkResourcesForLiveStreamingWhilePaused"] as? NSNumber)?.boolValue ?? false
            loadControl.preferredPeakBitRate = (map["preferredPeakBitRate"] as? NSNumber)?.doubleValue
            automaticallyWaitsToMinimizeStalling = (map["automaticallyWaitsToMinimizeStalling"] as? NSNumber)?.boolValue ?? false
        }

        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
        if handleInterruptions {
            observeAudioSession()
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        handleKeyValueChange(keyPath, of: object, change: change)
    }

    /// Converts a time to whole milliseconds, mapping non-numeric times to 0.
    static func milliseconds(of time: CMTime) -> Int {
        let seconds = CMTimeGetSeconds(time)
        if seconds.isNaN { return 0 }
        return Int(max(Double(Int32.min), min(Double(Int32.max), 1000 * seconds)))
    }

    // MARK: - Disposal

    func dispose(calledFromDeinit: Bool) {
        // Late seek and notification callbacks check these first. Seeks still waiting for an item are completed here;
        // their closure answers the Flutter call only when this isn't called from deinit.
        disposed = true
        disposedFromDeinit = calledFromDeinit
        seekGeneration += 1
        for source in indexedAudioSources {
            source.cancelQueuedSeek()
        }
        for observer in audioSessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        audioSessionObservers = []
        // The player is only created by the first successful load, but the channels exist from init and must be
        // released either way.
        if let player {
            if processingState != .idle {
                player.pause()
                updatePosition()
                // If used just before destroying the current FlutterEngine, sending results in:
                // NSInternalInconsistencyException: 'Sending a message before the FlutterEngine has been run.'
                if !calledFromDeinit {
                    broadcastPlaybackEvent()
                }
                processingState = .idle
            }
            player.removeObserver(self, forKeyPath: "currentItem")
            player.removeObserver(self, forKeyPath: "timeControlStatus")
            self.player = nil
        }
        // Replying to a pending call also goes through the messenger.
        if !calledFromDeinit {
            playResult?([String: Any]())
            loadResult?(FlutterError(code: "\(errorAbort)", message: "Connection aborted", details: nil))
        }
        playResult = nil
        loadResult = nil
        for source in indexedAudioSources {
            removeItemObservers(source.playerItem)
            removeItemObservers(source.playerItem2)
        }
        indexedAudioSources = []
        audioSource = nil
        eventChannel.dispose(calledFromDeinit: calledFromDeinit)
        dataEventChannel.dispose(calledFromDeinit: calledFromDeinit)
        if !calledFromDeinit {
            methodChannel.setMethodCallHandler(nil)
        }
    }
}
