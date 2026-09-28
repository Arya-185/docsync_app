import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:open_wake_word/open_wake_word.dart';

/// The wake-word model the app ships: the phrase to show, and its asset.
class WakeModel {
  const WakeModel(this.phrase, this.asset);
  final String phrase;
  final String asset;

  /// The custom model, once trained (tool/wakeword/README.md). Picked up automatically when
  /// the file is in the bundle; until then the stock openWakeWord model stands in.
  static const heyDocSync = WakeModel('Hey DocSync', 'assets/wakeword/hey_docsync.onnx');
  static const heyJarvis = WakeModel('Hey Jarvis', 'assets/wakeword/hey_jarvis_v0.1.onnx');
}

/// On-device wake-word detection. An interface so the controller is testable without the
/// native engine; the real one is [OpenWakeWordEngine].
abstract class WakeWordEngine {
  /// Load the models. Returns the model in use, or null when the engine is unavailable on
  /// this phone (then the wake word is simply off — tapping the orb always works).
  Future<WakeModel?> init();

  /// Feed one 80 ms frame (1280 samples, 16 kHz PCM16) and return the highest wake
  /// probability (0..1) seen since the last call.
  double process(Int16List frame);

  void dispose();
}

/// openWakeWord over ONNX Runtime (the `open_wake_word` FFI plugin). Inference runs on the
/// plugin's own native threads; [process] only hands samples over.
class OpenWakeWordEngine implements WakeWordEngine {
  bool _ready = false;
  WakeModel? _model;

  @override
  Future<WakeModel?> init() async {
    if (_ready) return _model;
    final model = await _hasAsset(WakeModel.heyDocSync.asset)
        ? WakeModel.heyDocSync
        : WakeModel.heyJarvis;
    try {
      final ok = await OpenWakeWord.init(
        melModelAssetPath: 'assets/wakeword/melspectrogram.onnx',
        embModelAssetPath: 'assets/wakeword/embedding_model.onnx',
        wwModelAssetPaths: [model.asset],
      );
      if (!ok) return null;
    } catch (_) {
      return null; // no native library for this ABI, or a model failed to load
    }
    _ready = true;
    _model = model;
    return model;
  }

  @override
  double process(Int16List frame) {
    if (!_ready) return 0;
    OpenWakeWord.processAudio(frame);
    return OpenWakeWord.getProbability();
  }

  @override
  void dispose() {
    if (!_ready) return;
    _ready = false;
    OpenWakeWord.destroy();
  }

  static Future<bool> _hasAsset(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
