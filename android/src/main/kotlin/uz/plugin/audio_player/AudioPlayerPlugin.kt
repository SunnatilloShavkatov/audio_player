package uz.plugin.audio_player

import io.flutter.embedding.engine.FlutterEngine.EngineLifecycleListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding

/**
 * Only the engine lifecycle: Dart calls [AudioPlayerApi] through JNI, so there is no channel. Each attached engine
 * gets its own [AudioPlayerHost], keyed by its engine id; detaching or restarting an engine releases only its players.
 */
class AudioPlayerPlugin : FlutterPlugin {
    private var host: AudioPlayerHost? = null
    private var engineId: Long = AudioPlayerHost.NO_ENGINE
    private var engineLifecycleListener: EngineLifecycleListener? = null

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        // The id Dart reads from `PlatformDispatcher.instance.engineId`. The binding exposes it only through the
        // engine on every supported Flutter version.
        @Suppress("DEPRECATION")
        val id = binding.flutterEngine.engineId
        val attached = AudioPlayerHost(binding.applicationContext)
        host = attached
        engineId = id
        AudioPlayerHost.attach(id, attached)

        val listener = object : EngineLifecycleListener {
            override fun onPreEngineRestart() {
                // The Dart side is going away: nothing may be sent to it now.
                attached.restart()
            }

            override fun onEngineWillDestroy() {}
        }
        engineLifecycleListener = listener
        @Suppress("DEPRECATION")
        binding.flutterEngine.addEngineLifecycleListener(listener)
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        // Unregister so the engine does not keep this plugin's listener alive.
        engineLifecycleListener?.let {
            @Suppress("DEPRECATION")
            binding.flutterEngine.removeEngineLifecycleListener(it)
        }
        engineLifecycleListener = null

        val detached = host ?: return
        host = null
        // The engine is being destroyed: nothing may be sent now. Other engines keep their players.
        AudioPlayerHost.detach(engineId, detached)
    }
}
