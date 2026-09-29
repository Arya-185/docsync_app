import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';

import 'tts_player.dart';

/// Spoken replies from the phone's own text-to-speech engine (`flutter_tts`) — free, offline,
/// and with no server round trip per sentence.
///
/// It is a [SpeechPlayer] so the voice session's queue/drain/stop/barge-in logic is unchanged;
/// the only difference is what goes in: TEXT via [enqueueText] rather than MP3 bytes from the
/// server. [enqueue] (bytes) is not used for this player and is ignored.
class DeviceSpeechPlayer implements SpeechPlayer {
  DeviceSpeechPlayer([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  final List<({String text, String lang})> _queue = [];
  Completer<void> _drained = Completer<void>()..complete();
  bool _running = false;
  bool _ready = false;
  int _generation = 0;
  String? _lastLang;

  @override
  bool get busy => _running || _queue.isNotEmpty;

  @override
  Future<void> get drained => _drained.future;

  @override
  void enqueue(Future<Uint8List> audio) {
    audio.catchError((_) => Uint8List(0)); // not used by this player
  }

  /// Queue one sentence. [lang] is the BCP-47 code the user spoke (null = automatic).
  void enqueueText(String text, {String? lang}) {
    final t = text.trim();
    if (t.isEmpty) return;
    _queue.add((text: t, lang: languageFor(t, lang)));
    if (_drained.isCompleted) _drained = Completer<void>();
    if (!_running) unawaited(_pump(_generation));
  }

  /// The voice to use: the language the user spoke in; with none, Hindi when the sentence is
  /// written in Devanagari, else Indian English.
  static String languageFor(String text, String? spoken) {
    if (spoken != null && spoken.isNotEmpty) return spoken;
    return RegExp(r'[ऀ-ॿ]').hasMatch(text) ? 'hi-IN' : 'en-IN';
  }

  Future<void> _pump(int gen) async {
    _running = true;
    if (!_ready) {
      try {
        await _tts.awaitSpeakCompletion(true);
        await _tts.setSpeechRate(0.5);
        await _tts.setPitch(1.0);
      } catch (_) {}
      _ready = true;
    }
    while (_queue.isNotEmpty && gen == _generation) {
      final next = _queue.removeAt(0);
      try {
        if (next.lang != _lastLang) {
          await _tts.setLanguage(next.lang);
          _lastLang = next.lang;
        }
        await _tts.speak(next.text); // completes when the sentence has been spoken, or stopped
      } catch (_) {
        // A sentence the engine will not say is skipped rather than ending the reply.
      }
    }
    if (gen == _generation) {
      _running = false;
      if (!_drained.isCompleted) _drained.complete();
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _queue.clear();
    _running = false;
    try {
      await _tts.stop();
    } catch (_) {}
    if (!_drained.isCompleted) _drained.complete();
  }

  @override
  Future<void> dispose() => stop();
}
