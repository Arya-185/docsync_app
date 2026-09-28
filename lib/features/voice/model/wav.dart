import 'dart:typed_data';

/// Wrap raw PCM16 little-endian mono samples in a WAV container — what the speech proxy
/// uploads. 16 kHz mono is what Sarvam's recogniser is tuned for, and a 44-byte header is
/// all a WAV is, so there is no reason to pull in an encoder.
Uint8List pcm16ToWav(Uint8List pcm, {int sampleRate = 16000, int channels = 1}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final out = Uint8List(44 + pcm.length);
  final b = ByteData.sublistView(out);

  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out[at + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  b.setUint16(20, 1, Endian.little); // format = PCM
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, byteRate, Endian.little);
  b.setUint16(32, blockAlign, Endian.little);
  b.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  b.setUint32(40, pcm.length, Endian.little);
  out.setRange(44, out.length, pcm);
  return out;
}
