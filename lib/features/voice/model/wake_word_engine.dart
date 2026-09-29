import 'dart:typed_data';

/// The wake phrase the app listens for, as shown on the Voice screen and in Settings.
///
/// The openWakeWord engine (ONNX Runtime, ~16 MB of native code per CPU type) was removed to
/// shrink the APK: it only ever ran with a trained `hey_docsync.onnx`, which was never bundled.
/// Detection is Vosk's (VoskWakeWordEngine, via AutoWakeWordEngine); tool/wakeword/ still
/// documents the training route if a trained model is wanted later.
class WakeModel {
  const WakeModel(this.phrase);
  final String phrase;

  static const heyDocSync = WakeModel('Hey DocSync');
}

/// On-device wake-word detection. An interface so the controller is testable without the
/// native engine; the real one is AutoWakeWordEngine (vosk_speech.dart).
abstract class WakeWordEngine {
  /// Load the models. Returns the model in use, or null when the engine is unavailable on
  /// this phone (then the wake word is simply off — tapping the orb always works).
  Future<WakeModel?> init();

  /// Feed one 80 ms frame (1280 samples, 16 kHz PCM16) and return the highest wake
  /// probability (0..1) seen since the last call.
  double process(Int16List frame);

  void dispose();
}
