// Fakes for the voice stack: a mic that plays scripted audio, a speech server with scripted
// transcripts, a speaker that records what it was asked to say, and a wake-word engine.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:docsync_app/core/providers.dart';
import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/voice/controller/voice_session.dart';
import 'package:docsync_app/features/voice/controller/wake_word.dart';
import 'package:docsync_app/features/voice/model/audio_capture.dart';
import 'package:docsync_app/features/voice/model/google_speech.dart';
import 'package:docsync_app/features/voice/model/speech_repository.dart';
import 'package:docsync_app/features/voice/model/tts_player.dart';
import 'package:docsync_app/features/voice/model/wake_word_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scripted_chat_repository.dart';

Uint8List tone(int ms, double amp) {
  final n = 16000 * ms ~/ 1000;
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    b.setInt16(i * 2, (amp * 32767 * math.sin(2 * math.pi * 220 * i / 16000)).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Someone saying one thing: a beat of quiet, ~1 s of voice, then silence.
List<Uint8List> utterance() => [tone(300, 0), tone(900, 0.3), tone(1000, 0)];

/// Nobody saying anything, for longer than any listening window.
List<Uint8List> silence() => [tone(9000, 0)];

/// A mic that plays one script per start(), in order (silence once they run out).
class FakeCapture implements AudioCapture {
  FakeCapture(this.scripts, {this.permitted = true});
  final List<List<Uint8List>> scripts;
  final bool permitted;
  int starts = 0;
  final List<Object?> owners = [];
  Object? owner;
  StreamController<Uint8List>? _c;

  bool get running => _c != null && !_c!.isClosed;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<Uint8List>> start({Object? owner}) async {
    await _close();
    final script = starts < scripts.length ? scripts[starts] : silence();
    starts++;
    owners.add(owner);
    this.owner = owner;
    final c = _c = StreamController<Uint8List>();
    () async {
      for (final block in script) {
        for (var i = 0; i < block.length; i += 640) {
          if (c.isClosed) return;
          c.add(Uint8List.sublistView(block, i, math.min(i + 640, block.length)));
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (!c.isClosed) await c.close();
    }();
    return c.stream;
  }

  @override
  Future<void> stop({Object? owner}) async {
    if (owner != null && !identical(owner, this.owner)) return;
    await _close();
  }

  Future<void> _close() async {
    final c = _c;
    _c = null;
    owner = null;
    if (c != null && !c.isClosed) await c.close();
  }

  @override
  Future<void> dispose() => _close();
}

/// Transcribes each utterance as the next entry of [transcripts] ('' once they run out).
class FakeSpeech implements SpeechRepository {
  FakeSpeech(List<String> transcripts, {this.fail}) : _queue = [...transcripts];
  final List<String> _queue;
  final SpeechException? fail;
  final List<({int bytes, String? lang})> heard = [];
  final List<String> spoken = [];

  @override
  Future<Transcript> transcribe(Uint8List wav, {String? lang, CancelToken? cancel}) async {
    heard.add((bytes: wav.length, lang: lang));
    if (fail != null) throw fail!;
    return Transcript(_queue.isEmpty ? '' : _queue.removeAt(0), 'hi-IN');
  }

  @override
  Future<Uint8List> synthesize(String text,
      {String? lang, String? speaker, double pace = 1.0, CancelToken? cancel}) async {
    spoken.add(text);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The phone's recogniser: each listen() takes the next entry of [heard] — a String is what was
/// said, a SpeechException is how it failed ('' once they run out).
class FakeLive implements LiveRecognizer {
  FakeLive(List<Object> heard, {this.isAvailable = true}) : _queue = [...heard];
  final List<Object> _queue;
  final bool isAvailable;
  final List<({String? lang, Duration noSpeech})> listens = [];
  int finishes = 0;
  int cancels = 0;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<Transcript> listen({
    String? lang,
    Duration noSpeech = const Duration(seconds: 8),
    void Function(double level)? onLevel,
    void Function(String words)? onPartial,
  }) async {
    listens.add((lang: lang, noSpeech: noSpeech));
    await Future<void>.delayed(Duration.zero);
    final next = _queue.isEmpty ? '' : _queue.removeAt(0);
    if (next is SpeechException) throw next;
    final words = next as String;
    if (words.isNotEmpty) {
      onLevel?.call(0.6);
      onPartial?.call(words.split(' ').first);
    }
    return Transcript(words, lang ?? 'en-IN');
  }

  @override
  Future<void> finish() async => finishes++;

  @override
  Future<void> cancel() async => cancels++;
}

/// A speaker that finishes instantly — or, with [holdPlayback], keeps its FIRST reply playing
/// until stopped (so there is something to talk over); later replies finish instantly.
class FakePlayer implements SpeechPlayer {
  FakePlayer({this.holdPlayback = false});
  final bool holdPlayback;
  int enqueued = 0;
  int stops = 0;
  Completer<void>? _playing;
  bool _held = false;

  @override
  bool get busy => _playing != null && !_playing!.isCompleted;

  @override
  Future<void> get drained => _playing?.future ?? Future<void>.value();

  @override
  void enqueue(Future<Uint8List> audio) {
    enqueued++;
    if (holdPlayback && !_held) {
      _held = true;
      _playing = Completer<void>();
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    if (_playing != null && !_playing!.isCompleted) _playing!.complete();
  }

  @override
  Future<void> dispose() async {}
}

/// Probability [high] from frame [fromFrame] on, else 0.
class FakeWakeEngine implements WakeWordEngine {
  FakeWakeEngine({this.fromFrame = 1 << 30, this.high = 0.95, this.available = true});
  final int fromFrame;
  final double high;
  final bool available;
  int frames = 0;
  int inits = 0;

  @override
  Future<WakeModel?> init() async {
    inits++;
    return available ? WakeModel.heyDocSync : null;
  }

  @override
  double process(Int16List frame) => frames++ >= fromFrame ? high : 0.0;

  @override
  void dispose() {}
}

typedef VoiceHarness = ({
  ProviderContainer c,
  FakeCapture mic,
  FakeSpeech speech,
  FakePlayer player,
  ScriptedChatRepository chat,
});

Future<VoiceHarness> voiceHarness({
  required List<Map<String, dynamic>> script,
  List<List<Uint8List>> mic = const [],
  List<String> transcripts = const [],
  bool followUp = false,
  bool bargeIn = false,
  bool wakeWord = false,
  bool permitted = true,
  bool holdPlayback = false,
  SpeechException? sttFails,
  WakeWordEngine? wake,
  LiveRecognizer? live,
}) async {
  SharedPreferences.setMockInitialValues({
    'voice_follow_up': followUp,
    'voice_barge_in': bargeIn,
    'voice_wake_word': wakeWord,
  });
  final prefs = await SharedPreferences.getInstance();
  final capture = FakeCapture(mic, permitted: permitted);
  final speech = FakeSpeech(transcripts, fail: sttFails);
  final player = FakePlayer(holdPlayback: holdPlayback);
  final chat = ScriptedChatRepository(script);
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    chatRepositoryProvider.overrideWithValue(chat),
    audioCaptureProvider.overrideWithValue(capture),
    speechRepositoryProvider.overrideWithValue(speech),
    // Null by default: the recorder + [FakeSpeech] path, which most tests drive.
    liveRecognizerProvider.overrideWithValue(live),
    speechPlayerProvider.overrideWithValue(player),
    wakeWordEngineProvider.overrideWithValue(wake ?? FakeWakeEngine()),
  ]);
  addTearDown(c.dispose);
  c.listen(voiceSessionProvider, (_, _) {}); // kept alive like the screen does
  return (c: c, mic: capture, speech: speech, player: player, chat: chat);
}

/// Let the fake mic, the endpointer, the chat turns and any follow-ups run to quiet.
Future<void> settle(ProviderContainer c, {int maxTicks = 20000}) async {
  var idleFor = 0;
  for (var i = 0; i < maxTicks; i++) {
    await Future<void>.delayed(Duration.zero);
    idleFor = c.read(voiceSessionProvider).phase == VoicePhase.idle ? idleFor + 1 : 0;
    if (idleFor > 50) return;
  }
}
