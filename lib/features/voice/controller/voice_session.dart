import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/model/chat_models.dart';
import '../../settings/controller/settings_controller.dart';
import '../model/audio_capture.dart';
import '../model/speech_repository.dart';
import '../model/speech_text.dart';
import '../model/tts_player.dart';
import '../model/vad.dart';
import '../model/wav.dart';

final audioCaptureProvider = Provider<AudioCapture>((ref) {
  final c = RecordAudioCapture();
  ref.onDispose(c.dispose);
  return c;
});

final speechRepositoryProvider =
    Provider<SpeechRepository>((ref) => SpeechRepository(ref.watch(apiClientProvider)));

final speechPlayerProvider = Provider<SpeechPlayer>((ref) {
  final p = JustAudioSpeechPlayer();
  ref.onDispose(p.dispose);
  return p;
});

/// Where a spoken exchange is. One of these at a time; the orb draws it.
enum VoicePhase { idle, listening, transcribing, thinking, speaking }

class VoiceState {
  const VoiceState({
    this.phase = VoicePhase.idle,
    this.level = 0,
    this.asked,
    this.note,
  });

  final VoicePhase phase;

  /// Live mic loudness 0..1 while listening.
  final double level;

  /// The last question heard (and sent). Null until one is.
  final String? asked;

  /// A short line for the screen: "I didn't hear anything", an error.
  final String? note;

  bool get busy => phase != VoicePhase.idle;

  VoiceState copyWith({
    VoicePhase? phase,
    double? level,
    String? asked,
    String? note,
    bool clearNote = false,
  }) =>
      VoiceState(
        phase: phase ?? this.phase,
        level: level ?? this.level,
        asked: asked ?? this.asked,
        note: clearNote ? null : (note ?? this.note),
      );
}

final voiceSessionProvider =
    NotifierProvider<VoiceSession, VoiceState>(VoiceSession.new);

/// One spoken exchange: listen → transcribe → ask → speak the answer as it streams.
///
/// The question is an ordinary chat turn ([ChatController.send] with `voice: true`), so it lands
/// in the same conversation as typing, shows in Recent, and gets the same cards, pickers and
/// confirm buttons. This class owns only the audio on either side of it.
///
/// Speaking starts before the answer is finished: the chat state holds the answer text as it
/// streams, and every sentence that completes is sent to text-to-speech at once, so synthesis
/// of the next sentence overlaps playback of this one ([SpeechPlayer]).
class VoiceSession extends Notifier<VoiceState> {
  StreamSubscription<Uint8List>? _mic;
  EnergyVad? _vad;
  BytesBuilder? _pcm;
  SentenceChunker? _chunker;
  String? _speakLang;
  bool _turnActive = false;
  bool _muted = false;
  int _enqueued = 0;

  AudioCapture get _capture => ref.read(audioCaptureProvider);
  SpeechRepository get _speech => ref.read(speechRepositoryProvider);
  SpeechPlayer get _player => ref.read(speechPlayerProvider);

  @override
  VoiceState build() {
    ref.onDispose(() {
      _mic?.cancel();
      _mic = null;
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

  /// The orb was tapped. What that means depends on what is happening.
  Future<void> tap() async {
    switch (state.phase) {
      case VoicePhase.idle:
        await listen();
      case VoicePhase.listening:
        _vad?.finish(); // "I'm done" — end the utterance now
        await _endUtterance();
      case VoicePhase.transcribing:
        break; // a second or so; nothing useful to interrupt
      case VoicePhase.thinking:
        await ref.read(chatControllerProvider.notifier).stop();
      case VoicePhase.speaking:
        await stopSpeaking();
    }
  }

  /// Stop talking (the user interrupted). The answer stays on screen.
  Future<void> stopSpeaking() async {
    // Silence the rest of THIS answer too, not just the sentence playing: sentences still
    // streaming in would otherwise start talking again a second later.
    _muted = true;
    await _player.stop();
    state = state.copyWith(phase: VoicePhase.idle);
  }

  /// Open the mic and wait for one utterance.
  Future<void> listen() async {
    if (ref.read(chatControllerProvider).sending) {
      state = state.copyWith(note: 'Still answering — tap to stop it first.');
      return;
    }
    await _player.stop();
    if (!await _capture.hasPermission()) {
      state = state.copyWith(
          phase: VoicePhase.idle, note: 'Allow the microphone to talk to DocSync.');
      return;
    }
    _vad = EnergyVad(sampleRate: AudioCapture.sampleRate);
    _pcm = BytesBuilder(copy: false);
    state = state.copyWith(phase: VoicePhase.listening, level: 0, clearNote: true);
    try {
      final stream = await _capture.start();
      _mic = stream.listen(
        (chunk) {
          final vad = _vad;
          if (vad == null || vad.done) return;
          _pcm?.add(chunk);
          vad.add(chunk);
          state = state.copyWith(level: vad.level);
          if (vad.done) unawaited(_endUtterance());
        },
        onError: (_) => unawaited(_endUtterance()),
        cancelOnError: true,
      );
    } catch (_) {
      _vad = null;
      state = state.copyWith(phase: VoicePhase.idle, note: 'The microphone is busy.');
    }
  }

  Future<void> _endUtterance() async {
    final vad = _vad;
    if (vad == null) return; // already ended
    _vad = null;
    await _mic?.cancel();
    _mic = null;
    await _capture.stop();
    final pcm = _pcm?.takeBytes() ?? Uint8List(0);
    _pcm = null;

    if (vad.phase != VadPhase.ended) {
      state = state.copyWith(phase: VoicePhase.idle, level: 0, note: 'I didn\'t hear anything.');
      return;
    }
    state = state.copyWith(phase: VoicePhase.transcribing, level: 0);
    final hint = ref.read(settingsControllerProvider).voiceLang.code;
    try {
      final t = await _speech.transcribe(pcm16ToWav(pcm), lang: hint);
      if (t.text.isEmpty) {
        state = state.copyWith(phase: VoicePhase.idle, note: 'I didn\'t catch that.');
        return;
      }
      await ask(t.text, lang: hint ?? (t.languageCode.isEmpty ? null : t.languageCode));
    } on SpeechException catch (e) {
      state = state.copyWith(phase: VoicePhase.idle, note: e.message);
    }
  }

  /// Ask [text] as a voice turn and speak the answer. Also used for a tapped suggestion.
  Future<void> ask(String text, {String? lang}) async {
    final q = text.trim();
    if (q.isEmpty) return;
    _chunker = SentenceChunker();
    _speakLang = lang;
    _enqueued = 0;
    _muted = false;
    _turnActive = true;
    state = state.copyWith(phase: VoicePhase.thinking, asked: q, clearNote: true);

    final chat = ref.read(chatControllerProvider.notifier);
    final sent = await chat.send(q, voice: true, lang: lang);
    if (!ref.mounted) return;
    if (!sent) {
      _turnActive = false;
      state = state.copyWith(
          phase: VoicePhase.idle, note: 'Still answering — tap to stop it first.');
      return;
    }

    // The turn is over: whatever is left of the answer is the last sentence.
    final last = _lastAssistant(ref.read(chatControllerProvider));
    _speakAll(_chunker!.finish(last?.content ?? ''));
    if (_enqueued == 0 && last != null && (last.confirm != null || last.a2ui.isNotEmpty)) {
      // A picker or confirm card with no prose: say where to look rather than going silent.
      _speakAll(['Please check your screen.']);
    }
    _turnActive = false;

    if (_enqueued > 0 && !_muted) {
      await _player.drained;
      if (!ref.mounted) return;
    }
    if (state.phase == VoicePhase.speaking || state.phase == VoicePhase.thinking) {
      state = state.copyWith(phase: VoicePhase.idle);
    }
  }

  void _speakAll(List<String> sentences) {
    if (_muted) return;
    for (final s in sentences) {
      if (s.trim().isEmpty) continue;
      _enqueued++;
      _player.enqueue(_speech.synthesize(s, lang: _speakLang));
      if (state.phase == VoicePhase.thinking) {
        state = state.copyWith(phase: VoicePhase.speaking);
      }
    }
  }

  /// Forget the on-screen exchange (a new conversation).
  void reset() {
    if (state.busy) return;
    state = const VoiceState();
  }

  static ChatMessage? _lastAssistant(ChatState s) =>
      s.messages.isNotEmpty && !s.messages.last.isUser ? s.messages.last : null;

  static String? _answerOf(ChatState s) => _lastAssistant(s)?.content;
}
