package uz.plugin.audio_player

import io.flutter.embedding.engine.FlutterEngine.EngineLifecycleListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding

/**
 * Only the engine lifecycle: Dart calls [AudioPlayerApi] through JNI, so there is no channel. Each attached engine
 * gets its own [AudioPlayerHost]; detaching or restarting the engine releases its players.
 */
class AudioPlayerPlugin : FlutterPlugin {
    private var host: AudioPlayerHost? = null
    private var engineLifecycleListener: EngineLifecycleListener? = null

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        val attached = AudioPlayerHost(binding.applicationContext)
        host = attached
        AudioPlayerHost.current = attached

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
        if (AudioPlayerHost.current === detached) AudioPlayerHost.current = null
        // The engine is being destroyed: nothing may be sent now.
        detached.detach()
    }
}
