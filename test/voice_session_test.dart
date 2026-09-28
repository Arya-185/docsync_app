// One spoken exchange through the REAL VoiceSession and ChatController, with the mic, the
// speech server and the speaker faked: listen → endpoint → transcribe → voice turn → speak.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:docsync_app/core/providers.dart';
import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/voice/controller/voice_session.dart';
import 'package:docsync_app/features/voice/model/audio_capture.dart';
import 'package:docsync_app/features/voice/model/speech_repository.dart';
import 'package:docsync_app/features/voice/model/tts_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/scripted_chat_repository.dart';

Uint8List tone(int ms, double amp) {
  final n = 16000 * ms ~/ 1000;
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    b.setInt16(i * 2, (amp * 32767 * math.sin(2 * math.pi * 220 * i / 16000)).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

/// A mic that "hears" [script] in 20 ms chunks as fast as the test can take them.
class FakeCapture implements AudioCapture {
  FakeCapture(this.script, {this.permitted = true});
  final List<Uint8List> script;
  final bool permitted;
  int starts = 0;
  bool running = false;
  StreamController<Uint8List>? _c;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    running = true;
    final c = _c = StreamController<Uint8List>();
    () async {
      for (final block in script) {
        for (var i = 0; i < block.length; i += 640) {
          if (!running || c.isClosed) return;
          c.add(Uint8List.sublistView(block, i, math.min(i + 640, block.length)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    }();
    return c.stream;
  }

  @override
  Future<void> stop() async {
    running = false;
    await _c?.close();
  }

  @override
  Future<void> dispose() => stop();
}

class FakeSpeech implements SpeechRepository {
  FakeSpeech({this.transcript = 'kal subah 11 baje Amit ko call karna yaad dilana', this.fail});
  final String transcript;
  final SpeechException? fail;
  final List<({int bytes, String? lang})> heard = [];
  final List<({String text, String? lang})> spoken = [];

  @override
  Future<Transcript> transcribe(Uint8List wav, {String? lang, CancelToken? cancel}) async {
    heard.add((bytes: wav.length, lang: lang));
    if (fail != null) throw fail!;
    return Transcript(transcript, 'hi-IN');
  }

  @override
  Future<Uint8List> synthesize(String text,
      {String? lang, String? speaker, double pace = 1.0, CancelToken? cancel}) async {
    spoken.add((text: text, lang: lang));
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakePlayer implements SpeechPlayer {
  final List<Future<Uint8List>> queue = [];
  int stops = 0;
  Completer<void>? gate; // when set, "playback" lasts until the test completes it

  @override
  bool get busy => queue.isNotEmpty;

  @override
  Future<void> get drained => gate?.future ?? Future<void>.value();

  @override
  void enqueue(Future<Uint8List> audio) => queue.add(audio);

  @override
  Future<void> stop() async {
    stops++;
    if (gate != null && !gate!.isCompleted) gate!.complete();
  }

  @override
  Future<void> dispose() async {}
}

const answerScript = <Map<String, dynamic>>[
  {'type': 'conversation', 'id': 5, 'turn': 1},
  {'type': 'token', 'text': 'Theek hai, kal subah 11 baje ka reminder set kar diya hai. '},
  {'type': 'token', 'text': 'Amit Traders ko call karna hai.'},
  {'type': 'final', 'answer': 'Theek hai, kal subah 11 baje ka reminder set kar diya hai. Amit Traders ko call karna hai.'},
];

Future<({ProviderContainer c, FakeCapture mic, FakeSpeech speech, FakePlayer player, ScriptedChatRepository chat})>
    harness({
  List<Uint8List>? audio,
  FakeSpeech? speech,
  bool permitted = true,
  List<Map<String, dynamic>> script = answerScript,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final mic = FakeCapture(
    audio ?? [tone(300, 0), tone(900, 0.3), tone(1000, 0)],
    permitted: permitted,
  );
  final sp = speech ?? FakeSpeech();
  final player = FakePlayer();
  final chat = ScriptedChatRepository(script);
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    chatRepositoryProvider.overrideWithValue(chat),
    audioCaptureProvider.overrideWithValue(mic),
    speechRepositoryProvider.overrideWithValue(sp),
    speechPlayerProvider.overrideWithValue(player),
  ]);
  addTearDown(c.dispose);
  c.listen(voiceSessionProvider, (_, _) {}); // keep it alive like the screen does
  return (c: c, mic: mic, speech: sp, player: player, chat: chat);
}

/// Let the fake mic, the endpointer and the chat turn run to quiet.
Future<void> settle(ProviderContainer c) async {
  for (var i = 0; i < 400; i++) {
    await Future<void>.delayed(Duration.zero);
    final p = c.read(voiceSessionProvider).phase;
    if (i > 10 && p == VoicePhase.idle) return;
  }
}

void main() {
  test('speak → heard → asked as a voice turn → the answer is spoken sentence by sentence',
      () async {
    final h = await harness();
    await h.c.read(voiceSessionProvider.notifier).listen();
    expect(h.c.read(voiceSessionProvider).phase, VoicePhase.listening);
    await settle(h.c);

    expect(h.speech.heard, hasLength(1), reason: 'one utterance, transcribed once');
    expect(h.speech.heard.single.bytes, greaterThan(44), reason: 'a WAV with samples in it');
    expect(h.mic.running, isFalse, reason: 'the mic is closed once the utterance ends');

    expect(h.chat.asked, ['kal subah 11 baje Amit ko call karna yaad dilana']);
    expect(h.chat.voiceFlags.single.voice, isTrue);
    expect(h.chat.voiceFlags.single.lang, 'hi-IN', reason: 'the detected language is passed on');

    expect(h.speech.spoken.map((s) => s.text), [
      'Theek hai, kal subah 11 baje ka reminder set kar diya hai.',
      'Amit Traders ko call karna hai.',
    ]);
    expect(h.speech.spoken.every((s) => s.lang == 'hi-IN'), isTrue);

    final v = h.c.read(voiceSessionProvider);
    expect(v.phase, VoicePhase.idle);
    expect(v.asked, 'kal subah 11 baje Amit ko call karna yaad dilana');
  });

  test('silence is "I didn\'t hear anything", and nothing is sent anywhere', () async {
    final h = await harness(audio: [tone(9000, 0)]);
    await h.c.read(voiceSessionProvider.notifier).listen();
    await settle(h.c);
    expect(h.speech.heard, isEmpty);
    expect(h.chat.asked, isEmpty);
    expect(h.c.read(voiceSessionProvider).note, contains('didn\'t hear'));
  });

  test('no mic permission says so instead of silently doing nothing', () async {
    final h = await harness(permitted: false);
    await h.c.read(voiceSessionProvider.notifier).listen();
    expect(h.mic.starts, 0);
    expect(h.c.read(voiceSessionProvider).note, contains('microphone'));
  });

  test('out of speech credits is reported, and the question is not guessed at', () async {
    final h = await harness(speech: FakeSpeech(fail: SpeechException(SpeechError.quota)));
    await h.c.read(voiceSessionProvider.notifier).listen();
    await settle(h.c);
    expect(h.chat.asked, isEmpty);
    expect(h.c.read(voiceSessionProvider).note, contains('out of credits'));
  });

  test('a card with no prose tells the user to look at the screen', () async {
    final h = await harness(script: const [
      {'type': 'conversation', 'id': 6, 'turn': 1},
      {
        'type': 'confirm',
        'tool': 'send_invoice',
        'label': 'Send invoice #65',
        'summary': 'Send invoice #65 to Amit Traders',
        'commit_args': {'invoice_id': 65},
      },
    ]);
    await h.c.read(voiceSessionProvider.notifier).ask('invoice 65 bhej do');
    await settle(h.c);
    expect(h.speech.spoken.map((s) => s.text), ['Please check your screen.']);
  });

  test('tapping while it talks stops it, and the rest of that answer stays quiet', () async {
    final h = await harness();
    h.player.gate = Completer<void>();
    final session = h.c.read(voiceSessionProvider.notifier);
    final turn = session.ask('status batao');
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 20 && h.c.read(voiceSessionProvider).phase != VoicePhase.speaking; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(h.c.read(voiceSessionProvider).phase, VoicePhase.speaking);
    final before = h.speech.spoken.length;
    await session.tap();
    await turn;
    expect(h.player.stops, greaterThan(0));
    expect(h.c.read(voiceSessionProvider).phase, VoicePhase.idle);
    expect(h.speech.spoken.length, before, reason: 'no sentence is synthesised after the tap');
  });
}
