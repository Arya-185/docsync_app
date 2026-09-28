import 'dart:math' as math;
import 'dart:typed_data';

/// Where an utterance is, as far as the endpointer can tell.
enum VadPhase {
  /// Nothing said yet.
  waiting,

  /// The user is talking (or paused briefly mid-sentence).
  speaking,

  /// They talked and then stopped: the utterance is complete.
  ended,

  /// Nothing was said before the patience ran out.
  noSpeech,
}

/// An energy-based endpointer: decides when the user has started and finished talking from
/// the loudness of each audio frame, measured against a noise floor it keeps learning.
///
/// Why energy and not a model: the job is only "is someone talking into the phone right now",
/// on audio the OS has already echo-cancelled and noise-suppressed. A learnt floor handles a
/// quiet cabin and a noisy office alike, and it costs nothing to run on every 20 ms frame.
///
/// Feed it PCM16 little-endian mono via [add]; read [phase] and [level] after each call.
class EnergyVad {
  EnergyVad({
    this.sampleRate = 16000,
    this.startMs = 150,
    this.endSilenceMs = 800,
    this.noSpeechMs = 8000,
    this.maxMs = 20000,
    this.marginDb = 10,
    this.minSpeechDbfs = -48,
    this.calibrateMs = 250,
  });

  /// The first moments after the mic opens are taken as the room's noise, whatever they
  /// measure. Without this a room that is ALREADY noisy never teaches the floor (only quiet
  /// frames do), so steady office noise was heard as someone talking and never ended.
  ///
  /// The quietest calibration frame wins, and the result is capped at [maxFloorDbfs]: someone
  /// who starts talking the instant the mic opens (a follow-up) must not be learnt as "noise".
  final int calibrateMs;

  /// No room is louder than this at a phone mic after the OS noise suppressor.
  static const maxFloorDbfs = -25.0;

  final int sampleRate;

  /// Continuous speech needed before it counts as talking (skips clicks and coughs).
  final int startMs;

  /// Silence after talking that ends the utterance.
  final int endSilenceMs;

  /// How long to wait for the first word.
  final int noSpeechMs;

  /// Hard cap on one utterance.
  final int maxMs;

  /// How far above the noise floor a frame must be to be speech.
  final double marginDb;

  /// And never quieter than this, whatever the floor says.
  final double minSpeechDbfs;

  VadPhase _phase = VadPhase.waiting;
  VadPhase get phase => _phase;

  /// Loudness of the latest frame on a 0..1 scale, for the orb.
  double level = 0;

  double _floor = -60; // dBFS, learnt
  bool _calibrated = false;
  int _elapsedMs = 0;
  int _voicedRunMs = 0;
  int _silenceRunMs = 0;
  bool get done => _phase == VadPhase.ended || _phase == VadPhase.noSpeech;

  /// Force the end (the user tapped "done").
  void finish() {
    if (done) return;
    _phase = _phase == VadPhase.speaking ? VadPhase.ended : VadPhase.noSpeech;
  }

  /// Process one chunk of PCM16 LE mono. Chunk size is free; timing comes from its length.
  VadPhase add(Uint8List pcm) {
    if (done || pcm.length < 2) return _phase;
    final samples = pcm.length ~/ 2;
    final ms = (samples * 1000) ~/ sampleRate;
    final db = dbfs(pcm);
    level = ((db + 60) / 50).clamp(0.0, 1.0);
    final calibrating = _elapsedMs < calibrateMs;
    _elapsedMs += ms;
    if (calibrating) {
      final quietest = _calibrated ? math.min(_floor, db) : db;
      _floor = math.min(quietest, maxFloorDbfs);
      _calibrated = true;
      return _phase;
    }

    final threshold = math.max(_floor + marginDb, minSpeechDbfs);
    final voiced = db > threshold;

    if (!voiced) {
      // Only quiet frames teach the floor, and it rises slowly: speech must never become
      // the "noise" it is compared against.
      final rate = db < _floor ? 0.3 : 0.05;
      _floor += (db - _floor) * rate;
    }

    switch (_phase) {
      case VadPhase.waiting:
        _voicedRunMs = voiced ? _voicedRunMs + ms : 0;
        if (_voicedRunMs >= startMs) {
          _phase = VadPhase.speaking;
          _silenceRunMs = 0;
        } else if (_elapsedMs >= noSpeechMs) {
          _phase = VadPhase.noSpeech;
        }
        break;
      case VadPhase.speaking:
        _silenceRunMs = voiced ? 0 : _silenceRunMs + ms;
        if (_silenceRunMs >= endSilenceMs || _elapsedMs >= maxMs) {
          _phase = VadPhase.ended;
        }
        break;
      case VadPhase.ended:
      case VadPhase.noSpeech:
        break;
    }
    return _phase;
  }

  /// RMS loudness of PCM16 LE in dBFS (0 = full scale, silence ≈ -96).
  static double dbfs(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final n = pcm.length ~/ 2;
    if (n == 0) return -96;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += s * s;
    }
    final rms = math.sqrt(sum / n);
    return rms <= 1e-5 ? -96 : 20 * math.log(rms) / math.ln10;
  }
}
