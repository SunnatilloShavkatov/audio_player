package uz.plugin.audio_player

import io.flutter.embedding.engine.FlutterEngine.EngineLifecycleListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.plugin.common.MethodChannel

/**
 * AudioPlayerPlugin
 */
class AudioPlayerPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private var methodCallHandler: MainMethodCallHandler? = null
    private var engineLifecycleListener: EngineLifecycleListener? = null

    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        val handler = MainMethodCallHandler(binding.applicationContext, messenger)
        methodCallHandler = handler

        channel = MethodChannel(messenger, "uz.plugin.audio_player.methods").also {
            it.setMethodCallHandler(handler)
        }
        val listener = object : EngineLifecycleListener {
            override fun onPreEngineRestart() {
                handler.dispose()
            }

            override fun onEngineWillDestroy() {}
        }
        engineLifecycleListener = listener
        @Suppress("DEPRECATION")
        binding.flutterEngine.addEngineLifecycleListener(listener)
    }

    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        // Unregister so the engine does not keep this plugin's handler alive.
        engineLifecycleListener?.let {
            @Suppress("DEPRECATION")
            binding.flutterEngine.removeEngineLifecycleListener(it)
        }
        engineLifecycleListener = null

        channel?.setMethodCallHandler(null)
        channel = null

        methodCallHandler?.dispose()
        methodCallHandler = null
    }
}
