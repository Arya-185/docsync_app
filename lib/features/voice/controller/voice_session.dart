import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/controller/commit_ledger.dart';
import '../../chat/model/a2ui_actions.dart';
import '../../chat/model/chat_models.dart';
import '../../settings/controller/settings_controller.dart';
import '../model/audio_capture.dart';
import '../model/device_tts.dart';
import '../model/intent_lexicon.dart';
import '../model/speech_repository.dart';
import '../model/speech_text.dart';
import '../model/tts_player.dart';
import '../model/vad.dart';
import '../model/voice_choices.dart';
import '../model/voice_picker_matcher.dart';
import '../model/vosk_speech.dart';
import '../model/wav.dart';

final audioCaptureProvider = Provider<AudioCapture>((ref) {
  final c = RecordAudioCapture();
  ref.onDispose(c.dispose);
  return c;
});

/// Speech-to-text on the phone (Vosk) unless the user chose the server's Sarvam recogniser.
final speechRepositoryProvider = Provider<SpeechRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return ref.watch(settingsControllerProvider.select((s) => s.deviceStt))
      ? OnDeviceSpeechRepository(api)
      : SpeechRepository(api);
});

final speechPlayerProvider = Provider<SpeechPlayer>((ref) {
  // The phone's own voice (free, offline) unless the user chose the server's Sarvam voice.
  final device = ref.watch(settingsControllerProvider.select((s) => s.deviceVoice));
  final SpeechPlayer p = device ? DeviceSpeechPlayer() : JustAudioSpeechPlayer();
  ref.onDispose(p.dispose);
  return p;
});

/// Where a spoken exchange is. One of these at a time; the orb draws it.
enum VoicePhase { idle, listening, transcribing, thinking, speaking }

/// What the mic is listening FOR — it changes what the screen asks the user to say.
enum ListenFor {
  /// A new question (after a tap, or the wake word).
  question,

  /// A follow-up in the few seconds after a reply, without a tap.
  followUp,

  /// Yes or no, for a write waiting on Confirm.
  confirm,

  /// "Cancel" in the seconds before something is sent to a client.
  outboundCancel,

  /// Which of the options on screen.
  choice,
}

class VoiceState {
  const VoiceState({
    this.phase = VoicePhase.idle,
    this.listenFor = ListenFor.question,
    this.level = 0,
    this.asked,
    this.note,
  });

  final VoicePhase phase;
  final ListenFor listenFor;

  /// Live mic loudness 0..1 while listening.
  final double level;

  /// The last question heard (and sent). Null until one is.
  final String? asked;

  /// A short line for the screen: "I didn't hear anything", an error.
  final String? note;

  bool get busy => phase != VoicePhase.idle;

  VoiceState copyWith({
    VoicePhase? phase,
    ListenFor? listenFor,
    double? level,
    String? asked,
    String? note,
    bool clearNote = false,
  }) =>
      VoiceState(
        phase: phase ?? this.phase,
        listenFor: listenFor ?? this.listenFor,
        level: level ?? this.level,
        asked: asked ?? this.asked,
        note: clearNote ? null : (note ?? this.note),
      );
}

final voiceSessionProvider =
    NotifierProvider<VoiceSession, VoiceState>(VoiceSession.new);

/// A spoken CONVERSATION: listen → ask → speak the answer → then, without a tap, whatever the
/// answer calls for — a yes/no for a write, a choice from a picker, or just a few seconds for
/// a follow-up. Speaking over the reply interrupts it; "stop" / "ruko" ends it.
///
/// Every question is an ordinary chat turn ([ChatController.send] with `voice: true`), and
/// every answer to a card is EXACTLY the action a tap on that card produces (see
/// voice_choices.dart), committed through the same [CommitLedger] as the buttons. So voice can
/// never do anything the screen could not, and the two can never both do it.
class VoiceSession extends Notifier<VoiceState> {
  /// Bumped to abandon whatever loop is running (tap to stop, leaving the screen).
  int _gen = 0;

  // The utterance being heard right now, if any.
  EnergyVad? _vad;
  Completer<void>? _heard;

  // Streaming speech for the turn in flight.
  SentenceChunker? _chunker;
  String? _speakLang;
  bool _turnActive = false;
  bool _muted = false;
  int _enqueued = 0;
  _BargeIn? _barge;

  AudioCapture get _capture => ref.read(audioCaptureProvider);
  SpeechRepository get _speech => ref.read(speechRepositoryProvider);
  SpeechPlayer get _player => ref.read(speechPlayerProvider);
  AppSettings get _settings => ref.read(settingsControllerProvider);

  /// Spoken-reply timings. Constants, not settings: they are tuned together.
  static const followUpMs = 7000;
  static const confirmMs = 7000;
  static const outboundCancelMs = 3500;

  @override
  VoiceState build() {
    ref.onDispose(() {
      _gen++;
      _barge?.stop();
    });
    // Speak each sentence of the answer as soon as it is complete.
    ref.listen<String?>(
      chatControllerProvider.select((s) => _answerOf(s)),
      (_, text) {
        if (!_turnActive || text == null) return;
        _speakAll(_chunker!.update(text));
      },
    );
    return const VoiceState();
  }

  // ---------------------------------------------------------------------------- controls

  /// The orb was tapped. What that means depends on what is happening.
  Future<void> tap() async {
    switch (state.phase) {
      case VoicePhase.idle:
        await listen();
      case VoicePhase.listening:
        _finishHearing(); // "I'm done" — end the utterance now
      case VoicePhase.transcribing:
        break; // a second or so; nothing useful to interrupt
      case VoicePhase.thinking:
        await ref.read(chatControllerProvider.notifier).stop();
      case VoicePhase.speaking:
        await stopSpeaking();
    }
  }

  /// Be quiet and stop the conversation. A running answer carries on on screen.
  Future<void> stopSpeaking() async {
    _gen++;
    _muted = true;
    await _barge?.stop();
    _barge = null;
    await _player.stop();
    state = state.copyWith(phase: VoicePhase.idle, level: 0);
  }

  /// Leave voice entirely: the screen went away or the app was backgrounded.
  Future<void> cancel() async {
    _gen++;
    _muted = true;
    _finishHearing();
    await _barge?.stop();
    _barge = null;
    await _player.stop();
    await _capture.stop();
    if (state.phase != VoicePhase.idle) {
      state = state.copyWith(phase: VoicePhase.idle, level: 0);
    }
  }

  /// Tap-to-talk (or the wake word): hear one question and run the conversation from it.
  Future<void> listen() async {
    if (ref.read(chatControllerProvider).sending) {
      state = state.copyWith(note: 'Still answering — tap to stop it first.');
      return;
    }
    final gen = ++_gen;
    await _player.stop();
    final q = await _hear(ListenFor.question, gen: gen);
    if (q == null || gen != _gen) return;
    if (q.text.isEmpty) {
      _idle(note: 'I didn\'t hear anything.');
      return;
    }
    await _converse(q.text, q.lang, gen);
  }

  /// Ask [text] as a voice turn and carry on the conversation. Also used for a tapped suggestion.
  Future<void> ask(String text, {String? lang}) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final gen = ++_gen;
    await _converse(q, lang, gen);
  }

  /// Forget the on-screen exchange (a new conversation).
  void reset() {
    if (state.busy) return;
    state = const VoiceState();
  }

  // ---------------------------------------------------------------------------- the loop

  Future<void> _converse(String question, String? lang, int gen) async {
    var q = question;
    var qLang = lang;
    for (var turns = 0; turns < 12 && gen == _gen; turns++) {
      final next = await _turn(q, qLang, gen);
      if (next == null || gen != _gen) break;
      q = next.text;
      qLang = next.lang ?? qLang;
    }
    if (gen == _gen) _idle();
  }

  /// One question and everything its answer calls for. Returns the next thing the user said,
  /// or null when the conversation is over.
  Future<_Heard?> _turn(String q, String? lang, int gen) async {
    _chunker = SentenceChunker();
    _speakLang = lang;
    _enqueued = 0;
    _muted = false;
    _turnActive = true;
    state = state.copyWith(phase: VoicePhase.thinking, asked: q, clearNote: true);

    final chat = ref.read(chatControllerProvider.notifier);
    final sent = await chat.send(q, voice: true, lang: lang);
    if (!ref.mounted || gen != _gen) {
      _turnActive = false;
      return null;
    }
    if (!sent) {
      _turnActive = false;
      _idle(note: 'Still answering — tap to stop it first.');
      return null;
    }

    // The turn is over: whatever is left of the answer is the last sentence.
    final last = _lastAssistant(ref.read(chatControllerProvider));
    _speakAll(_chunker!.finish(last?.content ?? ''));
    final confirm = last == null ? null : _openConfirm(last);
    final choices = last == null ? null : choicesOf(last);
    if (_enqueued == 0 && confirm == null && choices != null && !_isPicker(choices)) {
      // Chips with no prose: nothing to say; the follow-up window below still listens.
    } else if (_enqueued == 0 && confirm == null && (last?.a2ui.isNotEmpty ?? false) &&
        choices == null) {
      _speakAll(['Please check your screen.']);
    }
    _turnActive = false;

    // Let it finish talking — or hear the user talk over it.
    final interrupted = await _drainOrInterrupt(gen);
    if (gen != _gen) return null;
    if (interrupted != null) return _afterInterruption(interrupted, gen);

    if (confirm != null) return _confirmByVoice(confirm, gen);
    if (choices != null && _isPicker(choices)) return _chooseByVoice(choices, gen);
    if (!_settings.followUp) return null;

    final heard = await _hear(ListenFor.followUp, gen: gen, noSpeechMs: followUpMs);
    if (heard == null || heard.text.isEmpty || gen != _gen) return null;
    if (isStopCommand(heard.text)) return null;
    // A short reply that names a chip ("mark it paid", "undo") is that chip.
    if (choices != null && heard.text.split(' ').length <= 5) {
      final i = matchOption(heard.text, [for (final o in choices.options) o.label]);
      final text = i == null ? null : _sentenceOf(choices.options[i].action);
      if (text != null) return _Heard(text, heard.lang);
    }
    return heard;
  }

  /// A write waiting on Confirm: ask aloud, then do exactly what the buttons do.
  Future<_Heard?> _confirmByVoice(VoiceConfirm c, int gen) async {
    final conv = ref.read(chatControllerProvider).conversationId;
    final ledger = ref.read(commitLedgerProvider.notifier);
    final summary = c.summary.isEmpty ? 'I need your confirmation.' : speakable(c.summary);
    await _say(['$summary Shall I go ahead?'], gen);

    for (var attempt = 0; attempt < 2 && gen == _gen; attempt++) {
      final heard = await _hear(ListenFor.confirm, gen: gen, noSpeechMs: confirmMs);
      if (heard == null || gen != _gen) return null;
      // Answered on screen meanwhile? Then there is nothing left to ask.
      if (ledger.entry(conv, c.name, c.args) != null) return null;
      if (heard.text.isEmpty) {
        await _say(['I\'ll leave it on your screen.'], gen);
        return null;
      }
      switch (classifyReply(heard.text)) {
        case ReplyIntent.yes:
          if (c.outbound) {
            await _say(['Sending in three seconds. Say cancel to stop.'], gen);
            final wait =
                await _hear(ListenFor.outboundCancel, gen: gen, noSpeechMs: outboundCancelMs);
            if (gen != _gen) return null;
            final said = wait?.text ?? '';
            final i = said.isEmpty ? null : classifyReply(said);
            if (i == ReplyIntent.no || i == ReplyIntent.stop || i == ReplyIntent.unclear) {
              ledger.cancel(conv, c.name, c.args);
              await _say(['Okay, I haven\'t sent it.'], gen);
              return null;
            }
          }
          state = state.copyWith(phase: VoicePhase.thinking);
          final res = await ledger.commit(conv, c.name, c.args);
          if (gen != _gen) return null;
          await _say([res.message.isEmpty ? (res.ok ? 'Done.' : 'That didn\'t work.') : speakable(res.message)], gen);
          return null;
        case ReplyIntent.no:
        case ReplyIntent.stop:
          ledger.cancel(conv, c.name, c.args);
          await _say(['Okay, cancelled.'], gen);
          return null;
        case ReplyIntent.other:
          return heard; // a new request; the card stays on screen
        case ReplyIntent.unclear:
          if (attempt == 0) await _say(['Sorry, was that a yes or a no?'], gen);
      }
    }
    if (gen == _gen) await _say(['I\'ll leave it on your screen.'], gen);
    return null;
  }

  /// A picker on screen: read the options, then send the choice the way a tap would.
  Future<_Heard?> _chooseByVoice(VoiceChoices ch, int gen) async {
    final labels = [for (final o in ch.options) _spokenLabel(o.label)];
    final q = ch.question.isEmpty ? 'Which one?' : speakable(ch.question);
    const ord = ['First', 'Second', 'Third', 'Fourth'];
    if (labels.length <= 4) {
      await _say([
        '$q ${[for (var i = 0; i < labels.length; i++) '${ord[i]}, ${labels[i]}.'].join(' ')}'
      ], gen);
    } else {
      await _say(['$q Say the name, or first, second, and so on.'], gen);
    }

    for (var attempt = 0; attempt < 2 && gen == _gen; attempt++) {
      final heard = await _hear(ListenFor.choice, gen: gen, noSpeechMs: confirmMs);
      if (heard == null || gen != _gen) return null;
      if (heard.text.isEmpty) break;
      final i = matchOption(heard.text, [for (final o in ch.options) o.label]);
      if (i != null) {
        final text = _sentenceOf(ch.options[i].action);
        if (text != null) return _Heard(text, heard.lang);
      }
      final intent = classifyReply(heard.text);
      if (intent == ReplyIntent.no || intent == ReplyIntent.stop) {
        await _say(['Okay.'], gen);
        return null;
      }
      if (heard.text.split(' ').length > 4) return heard; // a new request instead
      if (attempt == 0) await _say(['Sorry, which one?'], gen);
    }
    if (gen == _gen) await _say(['I\'ll leave the options on your screen.'], gen);
    return null;
  }

  /// The user talked over the reply. "Stop" ends it; anything else is the next question.
  Future<_Heard?> _afterInterruption(Uint8List pcm, int gen) async {
    state = state.copyWith(phase: VoicePhase.transcribing, level: 0);
    final t = await _transcribe(pcm);
    if (t == null || gen != _gen) return null;
    if (t.text.isEmpty || isStopCommand(t.text)) {
      if (ref.read(chatControllerProvider).sending) {
        await ref.read(chatControllerProvider.notifier).stop();
      }
      return null;
    }
    // A new question while the old answer is still being written: stop that one first, and
    // wait for it to end — a conversation takes one turn at a time.
    if (ref.read(chatControllerProvider).sending) {
      await ref.read(chatControllerProvider.notifier).stop();
      for (var i = 0; i < 300 && ref.read(chatControllerProvider).sending; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    return t;
  }

  // ---------------------------------------------------------------------------- speaking

  void _speakAll(List<String> sentences) {
    if (_muted) return;
    for (final s in sentences) {
      if (s.trim().isEmpty) continue;
      _enqueued++;
      final player = _player;
      if (player is DeviceSpeechPlayer) {
        player.enqueueText(s, lang: _speakLang);
      } else {
        player.enqueue(_speech.synthesize(s, lang: _speakLang));
      }
      if (state.phase == VoicePhase.thinking) {
        state = state.copyWith(phase: VoicePhase.speaking);
        _startBargeIn();
      }
    }
  }

  /// Say [sentences] and wait (or be interrupted — which here simply ends the prompt).
  Future<void> _say(List<String> sentences, int gen) async {
    if (gen != _gen) return;
    _muted = false;
    _enqueued = 0;
    state = state.copyWith(phase: VoicePhase.thinking);
    _speakAll(sentences);
    await _drainOrInterrupt(gen);
  }

  /// Wait for everything queued to play. Returns the audio of an interruption, if the user
  /// talked over it (barge-in), else null.
  Future<Uint8List?> _drainOrInterrupt(int gen) async {
    if (_enqueued == 0 || _muted) {
      await _barge?.stop();
      _barge = null;
      return null;
    }
    final barge = _barge;
    Uint8List? interruption;
    if (barge != null) {
      final first = await Future.any<Object?>([
        _player.drained.then((_) => #drained),
        barge.triggered.then((_) => #barge),
      ]);
      if (first == #barge && gen == _gen) {
        _muted = true;
        await _player.stop();
        state = state.copyWith(phase: VoicePhase.listening, listenFor: ListenFor.question);
        interruption = await barge.utterance;
      }
      await barge.stop();
      if (identical(_barge, barge)) _barge = null;
    } else {
      await _player.drained;
    }
    if (gen == _gen && state.phase == VoicePhase.speaking) {
      state = state.copyWith(phase: VoicePhase.thinking);
    }
    return interruption;
  }

  void _startBargeIn() {
    if (!_settings.bargeIn || _barge != null) return;
    _barge = _BargeIn(_capture, onLevel: (l) {
      if (state.phase == VoicePhase.listening) state = state.copyWith(level: l);
    })
      ..start();
  }

  // ---------------------------------------------------------------------------- hearing

  /// Open the mic for one utterance, then transcribe it. Returns null on an error (with the
  /// note set), an empty [_Heard] when nothing was said.
  Future<_Heard?> _hear(ListenFor what, {required int gen, int noSpeechMs = 8000}) async {
    if (!await _capture.hasPermission()) {
      _idle(note: 'Allow the microphone to talk to DocSync.');
      return null;
    }
    if (gen != _gen) return null;
    final vad = _vad = EnergyVad(sampleRate: AudioCapture.sampleRate, noSpeechMs: noSpeechMs);
    final pcm = BytesBuilder(copy: false);
    final done = _heard = Completer<void>();
    state = state.copyWith(
        phase: VoicePhase.listening, listenFor: what, level: 0, clearNote: true);
    StreamSubscription<Uint8List>? sub;
    try {
      final stream = await _capture.start(owner: this);
      sub = stream.listen(
        (chunk) {
          if (vad.done) return;
          pcm.add(chunk);
          vad.add(chunk);
          state = state.copyWith(level: vad.level);
          if (vad.done && !done.isCompleted) done.complete();
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future;
    } catch (_) {
      _idle(note: 'The microphone is busy.');
      return null;
    } finally {
      await sub?.cancel();
      await _capture.stop(owner: this);
      _vad = null;
      _heard = null;
    }
    if (gen != _gen) return null;
    if (vad.phase != VadPhase.ended) return const _Heard('', null);
    state = state.copyWith(phase: VoicePhase.transcribing, level: 0);
    return _transcribe(pcm.takeBytes());
  }

  Future<_Heard?> _transcribe(Uint8List pcm) async {
    final hint = _settings.voiceLang.code;
    try {
      final t = await _speech.transcribe(pcm16ToWav(pcm), lang: hint);
      return _Heard(t.text, hint ?? (t.languageCode.isEmpty ? null : t.languageCode));
    } on SpeechException catch (e) {
      _idle(note: e.message);
      return null;
    }
  }

  void _finishHearing() {
    _vad?.finish();
    final d = _heard;
    if (d != null && !d.isCompleted) d.complete();
  }

  // ---------------------------------------------------------------------------- helpers

  void _idle({String? note}) {
    if (!ref.mounted) return;
    state = state.copyWith(phase: VoicePhase.idle, level: 0, note: note, clearNote: note == null);
  }

  /// The proposal on [m] that nobody has answered yet.
  VoiceConfirm? _openConfirm(ChatMessage m) {
    final c = confirmOf(m);
    if (c == null) return null;
    final conv = ref.read(chatControllerProvider).conversationId;
    return ref.read(commitLedgerProvider.notifier).entry(conv, c.name, c.args) == null ? c : null;
  }

  /// A question with fixed answers (a picker), as opposed to optional chips.
  static bool _isPicker(VoiceChoices ch) =>
      ch.options.isNotEmpty && ch.options.first.action is SendChat && ch.question.isNotEmpty &&
      ch.question.trim().endsWith('?');

  static String? _sentenceOf(A2uiAction a) => a is SendChat ? a.text : null;

  /// "Acme Traders — file_no 1201" is read as "Acme Traders".
  static String _spokenLabel(String label) => speakable(label.split(' — ').first);

  static ChatMessage? _lastAssistant(ChatState s) =>
      s.messages.isNotEmpty && !s.messages.last.isUser ? s.messages.last : null;

  static String? _answerOf(ChatState s) => _lastAssistant(s)?.content;
}

class _Heard {
  const _Heard(this.text, this.lang);
  final String text;
  final String? lang;
}

/// Listening WHILE the app talks, for the user cutting in.
///
/// Stricter than normal listening — louder than the room by more, for longer — because the
/// phone's own voice leaks into the mic even through the echo canceller, and a reply that
/// interrupts itself is worse than one that cannot be interrupted by voice (tap always works).
class _BargeIn {
  _BargeIn(this._capture, {this.onLevel});
  final AudioCapture _capture;
  final void Function(double level)? onLevel;

  final _vad = EnergyVad(
    marginDb: 16,
    startMs: 300,
    endSilenceMs: 800,
    noSpeechMs: 1 << 30,
    maxMs: 15000,
    calibrateMs: 400,
  );
  final _pre = <Uint8List>[]; // the last ~400 ms before the user was detected
  final _pcm = BytesBuilder(copy: false);
  final _triggered = Completer<void>();
  final _done = Completer<Uint8List?>();
  StreamSubscription<Uint8List>? _sub;
  bool _stopped = false;

  Future<void> get triggered => _triggered.future;
  Future<Uint8List?> get utterance => _done.future;

  Future<void> start() async {
    try {
      final s = await _capture.start(owner: this);
      if (_stopped) {
        await _capture.stop(owner: this);
        return;
      }
      _sub = s.listen(_onChunk, onError: (_) => stop(), onDone: () => _finish());
    } catch (_) {
      // No mic to spare: this reply simply cannot be interrupted by voice.
    }
  }

  void _onChunk(Uint8List chunk) {
    final wasSpeaking = _vad.phase == VadPhase.speaking;
    _vad.add(chunk);
    if (!_triggered.isCompleted) {
      _pre.add(chunk);
      while (_pre.length > 12) {
        _pre.removeAt(0);
      }
      if (_vad.phase == VadPhase.speaking && !wasSpeaking) {
        for (final c in _pre) {
          _pcm.add(c);
        }
        _pre.clear();
        _triggered.complete();
      }
      return;
    }
    _pcm.add(chunk);
    onLevel?.call(_vad.level);
    if (_vad.done) _finish();
  }

  void _finish() {
    if (!_done.isCompleted) {
      _done.complete(_triggered.isCompleted ? _pcm.takeBytes() : null);
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _sub?.cancel();
    await _capture.stop(owner: this);
    _finish();
  }
}
