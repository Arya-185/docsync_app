import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper over on-device speech-to-text for the mic button.
/// speech_to_text requests the RECORD_AUDIO permission itself during
/// [initialize], so no separate permission plugin is needed.
class VoiceService {
  final SpeechToText _stt = SpeechToText();
  bool _available = false;

  bool get isListening => _stt.isListening;

  Future<bool> ensureReady() async {
    if (_available) return true;
    _available = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    return _available;
  }

  /// Start listening. [onResult] fires with partial + final transcripts;
  /// [onDone] fires when recognition stops. [onLevel] reports the input level
  /// (roughly -2..10 dB) for a live mic animation. [localeId] (e.g. `hi_IN`)
  /// picks the recognition language; null uses the phone's default.
  Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
    void Function(double level)? onLevel,
    String? localeId,
  }) async {
    if (!await ensureReady()) return false;
    _stt.statusListener = (status) {
      if (status == 'done' || status == 'notListening') onDone?.call();
    };
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
    );
    return true;
  }

  Future<void> stop() => _stt.stop();
  Future<void> cancel() => _stt.cancel();
}

final voiceServiceProvider = Provider<VoiceService>((ref) => VoiceService());
