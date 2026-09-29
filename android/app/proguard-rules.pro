# Vosk (vosk_flutter_service) talks to its native library through JNA. Neither the Vosk nor the
# JNA AAR ships consumer rules, so everything R8 needs to know is here.

# JNA's desktop-only AWT helpers (Native$AWT) reference java.awt, which Android does not have.
# R8 treats a missing class as an error, so without this the release build fails outright.
-dontwarn java.awt.**

# JNA finds structures, callbacks and pointer types by reflection: keep all of it, sub-packages too.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }

# Vosk binds its native functions by method NAME (Native.register), and Model / Recognizer are
# JNA PointerTypes. A renamed method is an UnsatisfiedLinkError the first time the mic opens.
-keep class org.vosk.** { *; }
