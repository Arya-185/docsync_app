import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/controller/settings_controller.dart';
import '../model/audio_capture.dart';
import '../model/wake_word_engine.dart';
import 'voice_session.dart';

final wakeWordEngineProvider = Provider<WakeWordEngine>((ref) {
  final e = OpenWakeWordEngine();
  ref.onDispose(e.dispose);
  return e;
});

/// Is the Voice tab on screen, with the app in the foreground? Set by the shell and the
/// voice screen. The wake word listens ONLY while this is true.
final voiceForegroundProvider = NotifierProvider<VoiceForeground, bool>(VoiceForeground.new);

class VoiceForeground extends Notifier<bool> {
  bool _tab = true;
  bool _resumed = true;

  @override
  bool build() => true;

  void setTabVisible(bool v) {
    _tab = v;
    state = _tab && _resumed;
  }

  void setResumed(bool v) {
    _resumed = v;
    state = _tab && _resumed;
  }
}

enum WakeWordStatus {
  /// Turned off in Settings.
  off,

  /// On, but not listening right now (another tab, the app in the background, or the voice
  /// session is using the mic).
  paused,

  /// Loading the models.
  starting,

  /// Listening for the phrase.
  listening,

  /// The engine could not start on this phone; tap-to-talk still works.
  unavailable,
}

class WakeState {
  const WakeState(this.status, [this.phrase = 'Hey DocSync']);
  final WakeWordStatus status;
  final String phrase;
}

final wakeWordProvider = NotifierProvider<WakeWordController, WakeState>(WakeWordController.new);

/// Just the status, for widgets that only need to know whether it is listening.
final wakeWordStatusProvider = Provider<WakeWordStatus>((ref) => ref.watch(wakeWordProvider).status);

/// Listens for the wake phrase while — and only while — the app is open on the Voice tab, the
/// wake word is on, and the voice session is idle. On a detection it hands the mic to the
/// session ([VoiceSession.listen]) and resumes when the conversation is over.
///
/// Foreground only, by design (the owner's choice): no background service, nothing listening
/// with the screen off or the app closed.
class WakeWordController extends Notifier<WakeState> {
  StreamSubscription<Uint8List>? _mic;
  bool _running = false;
  bool _starting = false;
  WakeModel? _model;
  bool _unavailable = false;

  // Frame assembly and detection.
  final _frame = Int16List(frameSamples);
  int _fill = 0;
  int _framesSinceStart = 0;
  int _hits = 0;

  static const frameSamples = 1280; // 80 ms at 16 kHz — what the model is built for

  /// Frames ignored after (re)starting: the engine's windows still hold audio from before the
  /// gap, and a detection stitched across it is noise.
  static const warmupFrames = 25; // 2 s

  /// Consecutive frames over the threshold for a detection.
  static const hitsNeeded = 2;

  AudioCapture get _capture => ref.read(audioCaptureProvider);
  WakeWordEngine get _engine => ref.read(wakeWordEngineProvider);

  /// Sensitivity 0..1 → probability threshold (0.5 → 0.5; more sensitive → lower).
  static double thresholdFor(double sensitivity) => 0.8 - 0.6 * sensitivity.clamp(0.0, 1.0);

  @override
  WakeState build() {
    ref.onDispose(() {
      _mic?.cancel();
      _mic = null;
      _running = false;
    });
    ref.listen(settingsControllerProvider.select((s) => s.wakeWord), (_, _) => _reconcile());
    ref.listen(voiceForegroundProvider, (_, _) => _reconcile());
    ref.listen(voiceSessionProvider.select((v) => v.phase), (_, _) => _reconcile());
    Future.microtask(_reconcile);
    return WakeState(
      ref.read(settingsControllerProvider).wakeWord ? WakeWordStatus.paused : WakeWordStatus.off,
    );
  }

  bool get _shouldRun =>
      ref.read(settingsControllerProvider).wakeWord &&
      ref.read(voiceForegroundProvider) &&
      ref.read(voiceSessionProvider).phase == VoicePhase.idle &&
      !_unavailable;

  Future<void> _reconcile() async {
    if (!ref.mounted) return;
    final on = ref.read(settingsControllerProvider).wakeWord;
    if (!on) {
      await _stop();
      _set(WakeWordStatus.off);
      return;
    }
    if (_unavailable) {
      _set(WakeWordStatus.unavailable);
      return;
    }
    if (_shouldRun) {
      await _start();
    } else {
      await _stop();
      _set(WakeWordStatus.paused);
    }
  }

  Future<void> _start() async {
    if (_running || _starting) return;
    _starting = true;
    try {
      if (_model == null) {
        _set(WakeWordStatus.starting);
        _model = await _engine.init();
        if (_model == null) {
          _unavailable = true;
          _set(WakeWordStatus.unavailable);
          return;
        }
      }
      if (!_shouldRun || !await _capture.hasPermission()) {
        _set(WakeWordStatus.paused);
        return;
      }
      final stream = await _capture.start(owner: this);
      _fill = 0;
      _framesSinceStart = 0;
      _hits = 0;
      _running = true;
      _mic = stream.listen(_onChunk, onError: (_) => _stop(), onDone: () => _running = false);
      _set(WakeWordStatus.listening);
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    if (!_running && _mic == null) return;
    _running = false;
    await _mic?.cancel();
    _mic = null;
    await _capture.stop(owner: this);
  }

  void _onChunk(Uint8List chunk) {
    if (!_running) return;
    final data = ByteData.sublistView(chunk);
    final threshold = thresholdFor(ref.read(settingsControllerProvider).wakeSensitivity);
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      _frame[_fill++] = data.getInt16(i, Endian.little);
      if (_fill < frameSamples) continue;
      _fill = 0;
      final p = _engine.process(_frame);
      if (++_framesSinceStart <= warmupFrames) continue;
      _hits = p >= threshold ? _hits + 1 : 0;
      if (_hits >= hitsNeeded) {
        _hits = 0;
        unawaited(_detected());
        return;
      }
    }
  }

  Future<void> _detected() async {
    await _stop();
    if (!ref.mounted) return;
    // The session takes the mic; its phase change keeps this paused until it is idle again.
    unawaited(ref.read(voiceSessionProvider.notifier).listen());
  }

  void _set(WakeWordStatus s) {
    if (!ref.mounted) return;
    final phrase = _model?.phrase ?? state.phrase;
    if (state.status != s || state.phrase != phrase) state = WakeState(s, phrase);
  }
}
