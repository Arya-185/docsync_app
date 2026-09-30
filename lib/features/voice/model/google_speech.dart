import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_repository.dart';

/// A recogniser that owns the mic and decides for itself when the user has finished — the
/// opposite of [SpeechRepository.transcribe], which is handed a finished recording.
///
/// An interface so the voice session and dictation can be driven by a fake in tests; the real
/// one is [GoogleSpeechRecognizer].
abstract class LiveRecognizer {
  /// Is a recogniser there to use? Asks for the mic permission the first time.
  Future<bool> available();

  /// Listen for one utterance and return what was said ('' when nothing was, within
  /// [noSpeech]). [onPartial] gets the words so far while the user is still talking.
  /// Throws [SpeechException]; [SpeechError.recognizer] means another recogniser should try.
  Future<Transcript> listen({
    String? lang,
    Duration noSpeech = const Duration(seconds: 8),
    void Function(double level)? onLevel,
    void Function(String words)? onPartial,
  });

  /// "I'm done": stop now and return what was heard so far.
  Future<void> finish();

  /// Abandon the utterance; [listen] returns ''.
  Future<void> cancel();
}

/// Android's SpeechRecognizer — on almost every phone Google's recogniser — through the
/// speech_to_text plugin. Free, no key in the app, and far better with Indian names and
/// accents than energy endpointing plus a server round trip: it endpoints on the words, not on
/// loudness, and shows them as they are recognised.
///
/// One per app: the plugin is a singleton whose error and status listeners are set once.
class GoogleSpeechRecognizer implements LiveRecognizer {
  GoogleSpeechRecognizer._();
  static final GoogleSpeechRecognizer instance = GoogleSpeechRecognizer._();

  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  _Utterance? _now;

  // Utterances in a row where a voice was heard but no words came back. A recogniser that
  // hears and never transcribes (no Google account, a de-Googled phone, no network model) is
  // treated as missing after [_maxDeaf], so the server recogniser takes over for this run.
  int _deaf = 0;
  static const _maxDeaf = 2;

  /// How long to wait for the final result after [finish] before keeping the partial one.
  static const _finalWait = Duration(milliseconds: 1500);

  /// RMS dB that counts as a voice rather than the room (Android reports about -2 when quiet).
  /// Low on purpose: a false "voice" only means waiting for the recogniser's own timeout.
  static const _voiceDb = 2.0;

  /// No-speech windows this long or longer are left to the recogniser (plus [backstopGrace]).
  static const backstopFrom = Duration(seconds: 5);
  static const backstopGrace = Duration(seconds: 6);

  @override
  Future<bool> available() async {
    if (_deaf >= _maxDeaf) return false;
    if (_ready) return true;
    try {
      // Not cached when false: a refused permission can be granted later.
      _ready = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
        finalTimeout: _finalWait,
      );
    } catch (_) {
      _ready = false; // no plugin (tests, desktop) or no recognition service on the phone
    }
    return _ready;
  }

  @override
  Future<Transcript> listen({
    String? lang,
    Duration noSpeech = const Duration(seconds: 8),
    void Function(double level)? onLevel,
    void Function(String words)? onPartial,
  }) async {
    if (!await available()) throw SpeechException(SpeechError.recognizer, 'unavailable');
    await _abandon();
    if (_stt.isListening) await _stt.cancel();
    final locale = localeFor(lang, PlatformDispatcher.instance.locale);
    final u = _now = _Utterance(locale, onPartial);
    // Nobody spoke. A short window (the few seconds to say "cancel") is ours to end exactly.
    // A longer one is ended by the recogniser's own no-speech timeout, which knows speech has
    // begun even when it is quiet; our timer is only the backstop for one that never ends.
    final wait = noSpeech < backstopFrom ? noSpeech : noSpeech + backstopGrace;
    u.noSpeech = Timer(wait, () {
      if (identical(_now, u) && u.words.isEmpty) {
        unawaited(_stt.cancel());
        _end(u);
      }
    });
    try {
      await _stt.listen(
        onResult: (r) => _onResult(u, r),
        onSoundLevelChange: (db) {
          // Someone is talking and the words are on their way (slow networks take seconds):
          // from here the recogniser's own endpointing decides, not the no-speech timer.
          if (db >= _voiceDb && ++u.loud >= 2) u.noSpeech?.cancel();
          onLevel?.call(levelOf(db));
        },
        listenOptions: SpeechListenOptions(
          localeId: locale,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 30),
        ),
      );
    } catch (e) {
      _end(u, error: SpeechException(SpeechError.recognizer, '$e'));
    }
    return u.done.future;
  }

  @override
  Future<void> finish() async {
    final u = _now;
    if (u == null) return;
    if (u.words.isEmpty) {
      u.cancelled = true;
      await _stt.cancel();
      _end(u);
      return;
    }
    await _stt.stop();
    // The final result normally arrives within a moment; if not, keep what was shown.
    Timer(_finalWait + const Duration(milliseconds: 300), () => _end(u));
  }

  @override
  Future<void> cancel() async {
    final u = _now;
    if (u == null) return;
    u.words = '';
    u.cancelled = true;
    await _stt.cancel();
    _end(u);
  }

  Future<void> _abandon() async {
    final u = _now;
    if (u == null) return;
    u
      ..words = ''
      ..cancelled = true;
    _end(u);
  }

  void _onResult(_Utterance u, SpeechRecognitionResult r) {
    if (!identical(_now, u)) return;
    final words = r.recognizedWords.trim();
    if (words.isNotEmpty) {
      u.words = words;
      u.noSpeech?.cancel();
      u.onPartial?.call(words);
    }
    if (r.finalResult) _end(u);
  }

  void _onError(SpeechRecognitionError e) {
    final u = _now;
    if (u == null) return;
    final err = errorFor(e.errorMsg);
    // "No match" after words were shown still means those words.
    if (err == null || u.words.isNotEmpty) {
      _end(u);
    } else {
      _end(u, error: SpeechException(err, err == SpeechError.noAudio ? 'permission' : e.errorMsg));
    }
  }

  void _onStatus(String status) {
    final u = _now;
    if (u == null) return;
    if (status == SpeechToText.listeningStatus) u.started = true;
    // A "done" from the utterance before this one (cancelled a moment ago) is not this one's.
    if (status != SpeechToText.doneStatus || !u.started) return;
    // Done without a final result (some recognisers): give the plugin's own fallback a
    // moment, then keep the words heard so far.
    Timer(const Duration(milliseconds: 400), () => _end(u));
  }

  void _end(_Utterance u, {SpeechException? error}) {
    u.noSpeech?.cancel();
    if (identical(_now, u)) _now = null;
    if (u.done.isCompleted) return;
    if (error != null) {
      u.done.completeError(error);
    } else {
      if (!u.cancelled) _deaf = u.words.isNotEmpty ? 0 : (u.loud >= 2 ? _deaf + 1 : _deaf);
      u.done.complete(Transcript(u.words, u.locale));
    }
  }

  /// The recogniser's language: the one chosen in Settings, else the phone's own if it is an
  /// Indian English or Hindi locale, else Indian English — the clients, towns and Hinglish a
  /// CA firm talks about are recognised far better by en-IN than by en-US.
  static String localeFor(String? lang, Locale device) {
    if (lang != null && lang.isNotEmpty) return lang;
    final l = device.languageCode;
    if (device.countryCode == 'IN' && (l == 'en' || l == 'hi')) return '$l-IN';
    return 'en-IN';
  }

  /// Android reports loudness as RMS dB, roughly -2 (quiet) to 10 (shouting); the orb wants
  /// 0..1.
  static double levelOf(double db) => ((db + 2) / 12).clamp(0.0, 1.0);

  /// What a recogniser error means here; null when it only means nobody spoke.
  static SpeechError? errorFor(String code) {
    switch (code) {
      case 'error_no_match':
      case 'error_speech_timeout':
        return null;
      case 'error_permission':
        return SpeechError.noAudio;
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
      case 'error_server_disconnected':
      case 'error_too_many_requests':
        return SpeechError.failed;
      default: // busy, client, audio, language not supported/unavailable, unknown
        return SpeechError.recognizer;
    }
  }
}

class _Utterance {
  _Utterance(this.locale, this.onPartial);
  final String locale;
  final void Function(String words)? onPartial;
  final done = Completer<Transcript>();
  String words = '';
  bool started = false;
  bool cancelled = false;
  int loud = 0;
  Timer? noSpeech;
}
