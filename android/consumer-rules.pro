# Dart reaches these classes only through JNI (lib/src/bindings), so R8 must keep their names and members.
-keep class uz.plugin.audio_player.AudioPlayerApi { *; }
-keep interface uz.plugin.audio_player.AudioPlayerApi$* { *; }
