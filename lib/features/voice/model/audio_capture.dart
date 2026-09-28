import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// The microphone, as a stream of PCM16 little-endian mono chunks at [sampleRate].
///
/// ONE mic, several users: the wake-word listener, the voice session, barge-in and dictation
/// take turns with it. Each passes an [owner] token, and [stop] only stops the mic if the
/// caller still owns it — otherwise a listener that is shutting down a moment late would
/// close the recording the next user just opened, and the question would be cut off.
///
/// An interface so the voice session can be driven by recorded fixtures in tests; the real
/// one is [RecordAudioCapture].
abstract class AudioCapture {
  static const sampleRate = 16000;

  /// Ask for (or confirm) microphone permission.
  Future<bool> hasPermission();

  /// Start the mic for [owner] (taking it from whoever had it). Each event is a chunk of
  /// PCM16 LE mono samples.
  Future<Stream<Uint8List>> start({Object? owner});

  /// Stop the mic — only if [owner] is still the one using it (null stops it regardless).
  Future<void> stop({Object? owner});

  Future<void> dispose();
}

/// The phone's mic via `record`, set up for talking to an assistant rather than recording:
/// the voice-communication source with the OS echo canceller and noise suppressor on, which is
/// what lets it listen while the phone's own speaker is playing (barge-in).
class RecordAudioCapture implements AudioCapture {
  final AudioRecorder _rec = AudioRecorder();
  bool _running = false;
  Object? _owner;

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<Stream<Uint8List>> start({Object? owner}) async {
    if (_running) await _stopNow();
    _owner = owner;
    final s = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: AudioCapture.sampleRate,
      numChannels: 1,
      echoCancel: true,
      noiseSuppress: true,
      autoGain: true,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
      ),
    ));
    _running = true;
    return s;
  }

  @override
  Future<void> stop({Object? owner}) async {
    if (owner != null && !identical(owner, _owner)) return; // someone else has it now
    await _stopNow();
  }

  Future<void> _stopNow() async {
    if (!_running) return;
    _running = false;
    _owner = null;
    try {
      await _rec.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await _stopNow();
    await _rec.dispose();
  }
}
