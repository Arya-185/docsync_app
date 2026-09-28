import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Plays spoken replies in order, one clip per sentence.
///
/// Clips are enqueued as FUTURES so synthesis of sentence 2 overlaps playback of sentence 1:
/// the order is fixed at enqueue time, while the audio arrives whenever the server returns it.
abstract class SpeechPlayer {
  /// Queue a clip. [audio] resolves to MP3 bytes, or throws (that clip is skipped).
  void enqueue(Future<Uint8List> audio);

  /// Completes when everything queued so far has played (or was stopped).
  Future<void> get drained;

  /// True while a clip is playing or waiting to play.
  bool get busy;

  /// Stop now and drop the queue (the user interrupted).
  Future<void> stop();

  Future<void> dispose();
}

/// [SpeechPlayer] over just_audio, with the audio session set up for speech so it ducks
/// other audio and routes the way a call would (which the echo canceller expects).
class JustAudioSpeechPlayer implements SpeechPlayer {
  final AudioPlayer _player = AudioPlayer();
  final List<Future<Uint8List>> _queue = [];
  Completer<void> _drained = Completer<void>()..complete();
  bool _running = false;
  int _generation = 0; // bumped by stop(); a loop from an older generation exits
  int _seq = 0;
  bool _sessionReady = false;

  @override
  bool get busy => _running || _queue.isNotEmpty;

  @override
  Future<void> get drained => _drained.future;

  @override
  void enqueue(Future<Uint8List> audio) {
    // An unawaited failing future must not surface as an unhandled error before its turn.
    audio.catchError((_) => Uint8List(0));
    _queue.add(audio);
    if (_drained.isCompleted) _drained = Completer<void>();
    if (!_running) unawaited(_pump(_generation));
  }

  Future<void> _pump(int gen) async {
    _running = true;
    if (!_sessionReady) {
      try {
        final s = await AudioSession.instance;
        await s.configure(const AudioSessionConfiguration.speech());
      } catch (_) {}
      _sessionReady = true;
    }
    final dir = await getTemporaryDirectory();
    while (_queue.isNotEmpty && gen == _generation) {
      final next = _queue.removeAt(0);
      Uint8List bytes;
      try {
        bytes = await next;
      } catch (_) {
        continue; // one sentence failed to synthesise; say the rest
      }
      if (bytes.isEmpty || gen != _generation) continue;
      final f = File('${dir.path}${Platform.pathSeparator}tts_${_seq++ % 8}.mp3');
      try {
        await f.writeAsBytes(bytes, flush: true);
        await _player.setFilePath(f.path);
        await _player.play(); // completes when the clip ends, or when stopped
        await _player.stop();
      } catch (_) {
        // A clip that will not play is skipped rather than ending the reply.
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
      await _player.stop();
    } catch (_) {}
    if (!_drained.isCompleted) _drained.complete();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
