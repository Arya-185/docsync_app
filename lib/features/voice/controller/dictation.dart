import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/audio_capture.dart';
import '../model/google_speech.dart';
import '../model/speech_repository.dart';
import '../model/vad.dart';
import '../model/wav.dart';
import 'voice_session.dart';

final dictationProvider = Provider<Dictation>(
  (ref) => Dictation(
    ref.read(audioCaptureProvider),
    ref.watch(speechRepositoryProvider),
    ref.watch(liveRecognizerProvider),
  ),
);

/// Speak into a text field and get the text back.
///
/// The same recognisers as the voice screen, so a question dictated into the chat box comes
/// out the same as one spoken to the orb: the phone's Google recogniser when there is one
/// (words appear as they are said), else one recorded utterance transcribed by the server.
class Dictation {
  Dictation(this._capture, this._speech, [this._live]);
  final AudioCapture _capture;
  final SpeechRepository _speech;
  final LiveRecognizer? _live;

  EnergyVad? _vad;
  Completer<void>? _ended;
  bool _liveActive = false;

  bool get active => _ended != null || _liveActive;

  /// Listen until the user stops talking (or [finish] is called) and return the words.
  /// Returns '' when nothing was said. [onPartial] gets the words so far, when the recogniser
  /// can tell. Throws [SpeechException].
  Future<String> run({
    String? lang,
    void Function(double level)? onLevel,
    void Function()? onTranscribing,
    void Function(String words)? onPartial,
  }) async {
    if (active) return '';
    if (!await _capture.hasPermission()) {
      throw SpeechException(SpeechError.noAudio, 'permission');
    }
    final live = _live;
    if (live != null && await live.available()) {
      _liveActive = true;
      try {
        await _capture.stop(); // the recogniser opens its own mic
        final t = await live.listen(lang: lang, onLevel: onLevel, onPartial: onPartial);
        return t.text;
      } on SpeechException catch (e) {
        if (e.error != SpeechError.recognizer) rethrow;
        // No working recogniser on this phone: record and transcribe instead.
      } finally {
        _liveActive = false;
      }
    }
    final vad = _vad = EnergyVad(sampleRate: AudioCapture.sampleRate);
    final pcm = BytesBuilder(copy: false);
    final ended = _ended = Completer<void>();
    StreamSubscription<Uint8List>? sub;
    try {
      final stream = await _capture.start(owner: this);
      sub = stream.listen(
        (chunk) {
          if (vad.done) return;
          pcm.add(chunk);
          vad.add(chunk);
          onLevel?.call(vad.level);
          if (vad.done && !ended.isCompleted) ended.complete();
        },
        onError: (_) {
          if (!ended.isCompleted) ended.complete();
        },
        cancelOnError: true,
      );
      await ended.future;
    } finally {
      await sub?.cancel();
      await _capture.stop(owner: this);
      _vad = null;
      _ended = null;
    }
    if (vad.phase != VadPhase.ended) return '';
    onTranscribing?.call();
    final t = await _speech.transcribe(pcm16ToWav(pcm.takeBytes()), lang: lang);
    return t.text;
  }

  /// The user tapped the mic again: stop listening and transcribe what was said.
  void finish() {
    if (_liveActive) unawaited(_live?.finish());
    _vad?.finish();
    final e = _ended;
    if (e != null && !e.isCompleted) e.complete();
  }
}
