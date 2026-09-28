import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/audio_capture.dart';
import '../model/speech_repository.dart';
import '../model/vad.dart';
import '../model/wav.dart';
import 'voice_session.dart';

final dictationProvider = Provider<Dictation>(
  (ref) => Dictation(ref.read(audioCaptureProvider), ref.read(speechRepositoryProvider)),
);

/// Speak into a text field: record one utterance, transcribe it on the server, return the text.
///
/// The same mic, endpointer and Sarvam recogniser as the voice screen, so a Hinglish
/// question dictated into the chat box comes out the same as one spoken to the orb — the
/// phone's own recogniser picks one language and mangles the other.
class Dictation {
  Dictation(this._capture, this._speech);
  final AudioCapture _capture;
  final SpeechRepository _speech;

  EnergyVad? _vad;
  Completer<void>? _ended;

  bool get active => _ended != null;

  /// Record until the user stops talking (or [finish] is called), then transcribe.
  /// Returns '' when nothing was said. Throws [SpeechException].
  Future<String> run({
    String? lang,
    void Function(double level)? onLevel,
    void Function()? onTranscribing,
  }) async {
    if (active) return '';
    if (!await _capture.hasPermission()) {
      throw SpeechException(SpeechError.noAudio, 'permission');
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
    _vad?.finish();
    final e = _ended;
    if (e != null && !e.isCompleted) e.complete();
  }
}
