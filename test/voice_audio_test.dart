// The pure audio pieces of voice mode: the endpointer, the WAV wrapper, and what gets spoken.
//
// The endpointer is tested on synthetic PCM — silence, noise, a tone — because "did it hear me
// stop talking" is a property of the numbers, and a phone in a test rig is not reproducible.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docsync_app/features/voice/model/speech_text.dart';
import 'package:docsync_app/features/voice/model/vad.dart';
import 'package:docsync_app/features/voice/model/wav.dart';
import 'package:flutter_test/flutter_test.dart';

const rate = 16000;

/// [ms] of PCM16 LE: a 220 Hz tone at [amp] (0..1) plus uniform noise at [noise].
Uint8List pcm(int ms, {double amp = 0, double noise = 0, int seed = 1}) {
  final n = rate * ms ~/ 1000;
  final r = math.Random(seed);
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final v = amp * math.sin(2 * math.pi * 220 * i / rate) + noise * (r.nextDouble() * 2 - 1);
    b.setInt16(i * 2, (v.clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Feed [audio] to [vad] in 20 ms frames, the way the mic delivers it.
VadPhase feed(EnergyVad vad, Uint8List audio) {
  const frame = rate * 20 ~/ 1000 * 2;
  for (var i = 0; i < audio.length; i += frame) {
    vad.add(Uint8List.sublistView(audio, i, math.min(i + frame, audio.length)));
    if (vad.done) break;
  }
  return vad.phase;
}

void main() {
  group('endpointer', () {
    test('speech after a quiet room, then silence, ends the utterance', () {
      final vad = EnergyVad();
      expect(feed(vad, pcm(600, noise: 0.002)), VadPhase.waiting);
      expect(feed(vad, pcm(1200, amp: 0.3, noise: 0.002)), VadPhase.speaking);
      expect(feed(vad, pcm(1000, noise: 0.002)), VadPhase.ended);
    });

    test('a pause shorter than the end-silence does not cut the sentence', () {
      final vad = EnergyVad();
      feed(vad, pcm(500, noise: 0.002));
      feed(vad, pcm(800, amp: 0.3));
      expect(feed(vad, pcm(400, noise: 0.002)), VadPhase.speaking);
      expect(feed(vad, pcm(800, amp: 0.3)), VadPhase.speaking);
    });

    test('a click shorter than the start threshold is not speech', () {
      final vad = EnergyVad();
      feed(vad, pcm(500, noise: 0.002));
      expect(feed(vad, pcm(80, amp: 0.5)), VadPhase.waiting);
      expect(feed(vad, pcm(500, noise: 0.002)), VadPhase.waiting);
    });

    test('a noisy office raises the floor instead of counting as speech', () {
      final vad = EnergyVad(noSpeechMs: 4000);
      // Steady noise at about -30 dBFS — well above the absolute speech minimum.
      expect(feed(vad, pcm(5000, noise: 0.055)), VadPhase.noSpeech);
    });

    test('...and talking clearly over it is still heard', () {
      final vad = EnergyVad();
      feed(vad, pcm(1500, noise: 0.055));
      expect(feed(vad, pcm(800, amp: 0.6, noise: 0.055)), VadPhase.speaking);
    });

    test('nothing said before the patience runs out is noSpeech', () {
      final vad = EnergyVad(noSpeechMs: 2000);
      expect(feed(vad, pcm(2500)), VadPhase.noSpeech);
    });

    test('an endless talker is cut at the cap', () {
      final vad = EnergyVad(maxMs: 3000);
      expect(feed(vad, pcm(4000, amp: 0.3)), VadPhase.ended);
    });

    test('tapping done ends it: speech so far counts, none does not', () {
      final a = EnergyVad();
      feed(a, pcm(700, amp: 0.3));
      a.finish();
      expect(a.phase, VadPhase.ended);
      final b = EnergyVad();
      feed(b, pcm(700));
      b.finish();
      expect(b.phase, VadPhase.noSpeech);
    });

    test('talking from the very first frame (a follow-up) is still heard', () {
      final vad = EnergyVad();
      expect(feed(vad, pcm(800, amp: 0.3, noise: 0.002)), VadPhase.speaking);
      expect(feed(vad, pcm(1000, noise: 0.002)), VadPhase.ended);
    });

    test('level is 0..1 and louder is higher', () {
      final quiet = EnergyVad()..add(pcm(20, amp: 0.01));
      final loud = EnergyVad()..add(pcm(20, amp: 0.8));
      expect(quiet.level, inInclusiveRange(0, 1));
      expect(loud.level, greaterThan(quiet.level));
    });
  });

  test('WAV header describes 16 kHz mono PCM16 and carries the samples', () {
    final raw = pcm(100, amp: 0.2);
    final wav = pcm16ToWav(raw);
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(b.getUint16(20, Endian.little), 1); // PCM
    expect(b.getUint16(22, Endian.little), 1); // mono
    expect(b.getUint32(24, Endian.little), 16000);
    expect(b.getUint16(34, Endian.little), 16);
    expect(b.getUint32(40, Endian.little), raw.length);
    expect(wav.length, 44 + raw.length);
    expect(wav.sublist(44), raw);
  });

  group('speakable', () {
    test('markdown is not read aloud', () {
      final s = speakable('## Pending\n- **Amit Traders**: GSTR-3B\n- *Mehta & Co*: [ITR](https://x.io/a)');
      expect(s, isNot(contains('#')));
      expect(s, isNot(contains('*')));
      expect(s, isNot(contains('https')));
      expect(s, contains('Amit Traders'));
      expect(s, contains('ITR'));
    });

    test('list lines become separate sentences, not one run-on', () {
      expect(speakable('Two tasks are due:\n- File GSTR-1\n- Call Amit'),
          'Two tasks are due: File GSTR-1. Call Amit');
    });

    test('a table is read as values', () {
      final s = speakable('| Client | Due |\n|---|---|\n| Amit | 5 Oct |');
      expect(s, isNot(contains('|')));
      expect(s, isNot(contains('---')));
      expect(s, contains('Amit'));
    });

    test('snake_case is left alone', () {
      expect(speakable('file_no_2 is set'), 'file_no_2 is set');
    });
  });

  group('SentenceChunker', () {
    test('emits a sentence only once it is complete, then the rest at finish', () {
      final c = SentenceChunker();
      expect(c.update('Your reminder for tomorrow'), isEmpty);
      expect(c.update('Your reminder for tomorrow at 11 is set. I also'), ['Your reminder for tomorrow at 11 is set.']);
      expect(c.update('Your reminder for tomorrow at 11 is set. I also added a to-do'), isEmpty);
      expect(c.finish('Your reminder for tomorrow at 11 is set. I also added a to-do'), ['I also added a to-do']);
    });

    test('a very short sentence waits to join the next one', () {
      final c = SentenceChunker();
      expect(c.update('Done. '), isEmpty);
      expect(c.update('Done. The invoice for Amit Traders is sent. More'),
          ['Done. The invoice for Amit Traders is sent.']);
    });

    test('Hindi sentences end at a danda', () {
      final c = SentenceChunker();
      expect(c.update('आपका reminder कल सुबह 11 बजे के लिए set है। और'),
          ['आपका reminder कल सुबह 11 बजे के लिए set है।']);
    });

    test('a long answer stops at the budget and says where the rest is', () {
      final c = SentenceChunker(maxChars: 120);
      final text = List.generate(10, (i) => 'Task number $i is due this week for a client.').join(' ');
      final out = c.finish(text);
      expect(out.last, SentenceChunker.overflowNote);
      expect(out.sublist(0, out.length - 1).join(' ').length, lessThanOrEqualTo(120));
      expect(c.update('$text More.'), isEmpty, reason: 'nothing after the cap');
    });

    test('an answer rewritten at final is never re-spoken', () {
      final c = SentenceChunker();
      expect(c.update('Checking the client now. And'), ['Checking the client now.']);
      // `final` replaced the text with something shorter: say nothing twice.
      expect(c.finish('Checking.'), isEmpty);
    });
  });
}
