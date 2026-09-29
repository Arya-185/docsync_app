# Vosk (vosk_flutter_service) talks to its native library through JNA; keep it from R8.
-keep class com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }
