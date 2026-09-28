import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// The microphone, as a stream of PCM16 little-endian mono chunks at [sampleRate].
///
/// An interface so the voice session can be driven by recorded fixtures in tests; the real
/// one is [RecordAudioCapture].
abstract class AudioCapture {
  static const sampleRate = 16000;

  /// Ask for (or confirm) microphone permission.
  Future<bool> hasPermission();

  /// Start the mic. Each event is a chunk of PCM16 LE mono samples.
  Future<Stream<Uint8List>> start();

  /// Stop the mic. Safe to call when it is not running.
  Future<void> stop();

  Future<void> dispose();
}

/// The phone's mic via `record`, set up for talking to an assistant rather than recording:
/// the voice-communication source with the OS echo canceller and noise suppressor on, which is
/// what lets it listen while the phone's own speaker is playing (barge-in).
class RecordAudioCapture implements AudioCapture {
  final AudioRecorder _rec = AudioRecorder();
  bool _running = false;

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<Stream<Uint8List>> start() async {
    if (_running) await stop();
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
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _rec.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _rec.dispose();
  }
}
