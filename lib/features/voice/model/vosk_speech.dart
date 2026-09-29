import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';

import 'speech_repository.dart';
import 'wake_word_engine.dart';

/// Offline speech on the phone with Vosk (small Indian-English model): the wake phrase and the
/// transcription of what is said after it. Nothing leaves the phone for either.
///
/// The model is NOT bundled at the moment (36 MB of the APK; pubspec.yaml says how to put it
/// back). Without it every Vosk path reports itself unavailable: the wake word is off and speech
/// goes to the server recogniser. Loading from a download is the planned replacement.
///
/// One model, loaded once and shared: the model is the expensive part (tens of MB unpacked);
/// recognisers over it are cheap.
class VoskModels {
  VoskModels._();
  static final VoskModels instance = VoskModels._();

  static const asset = 'assets/vosk/vosk-model-small-en-in-0.4.zip';

  // Late: creating the plugin loads libvosk, which throws where the library is absent. Asking
  // bundled() (Settings does) must not need the native library at all.
  late final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Future<Model>? _model;
  Future<bool>? _bundled;

  /// Is the model in this build? Read from the asset manifest, so asking costs nothing even
  /// when the 36 MB zip is there.
  Future<bool> bundled() => _bundled ??= () async {
        try {
          final m = await AssetManifest.loadFromAssetBundle(rootBundle);
          return m.listAssets().contains(asset);
        } catch (_) {
          return false;
        }
      }();

  /// The loaded model. The first call unpacks the zip into app storage (a few seconds, once).
  Future<Model> model() => _model ??= () async {
        if (!await bundled()) throw StateError('The offline speech model is not in this build.');
        final path = await ModelLoader().loadFromAssets(asset);
        return _vosk.createModel(path);
      }();

  Future<Recognizer> recognizer({List<String>? grammar}) async => _vosk.createRecognizer(
        model: await model(),
        sampleRate: 16000,
        grammar: grammar,
      );
}

/// "Hey DocSync" with no training: a recogniser restricted to the phrase (plus `[unk]` for
/// everything else), so it can only ever report the phrase or nothing.
///
/// Spelled as the model knows the words — "docsync" is not in its vocabulary, "doc sync" is.
class VoskWakeWordEngine implements WakeWordEngine {
  static const grammar = ['hey doc sync', 'hi doc sync', 'doc sync', '[unk]'];

  Recognizer? _rec;
  Future<void> _chain = Future.value();
  int _pending = 0;
  int _latch = 0;

  @override
  Future<WakeModel?> init() async {
    if (_rec != null) return WakeModel.heyDocSync;
    try {
      _rec = await VoskModels.instance.recognizer(grammar: grammar);
      return WakeModel.heyDocSync;
    } catch (_) {
      return null; // no native library for this ABI, or the model failed to load
    }
  }

  /// Hands the frame to the recogniser (async, in order) and reports a detection made by an
  /// EARLIER frame: 1.0 for a few calls after the phrase was heard, else 0. The controller's
  /// "consecutive frames over the threshold" rule is satisfied by that latch.
  @override
  double process(Int16List frame) {
    final rec = _rec;
    if (rec == null) return 0;
    if (_pending < 12) {
      // a backlog means the phone is too slow; dropping audio beats hearing it late
      _pending++;
      final bytes = Uint8List.fromList(frame.buffer.asUint8List(frame.offsetInBytes, frame.lengthInBytes));
      _chain = _chain.then((_) async {
        try {
          final done = await rec.acceptWaveformBytes(bytes);
          final json = done ? await rec.getResult() : await rec.getPartialResult();
          if (heard(json)) {
            _latch = 3;
            await rec.reset();
          }
        } catch (_) {
        } finally {
          _pending--;
        }
      });
    }
    if (_latch > 0) {
      _latch--;
      return 1.0;
    }
    return 0;
  }

  /// Does a Vosk result (`{"text": …}` or `{"partial": …}`) contain the wake phrase?
  /// Plain "doc sync" counts only as a whole utterance; with "hey"/"hi" it may be a partial.
  static bool heard(String json) {
    String text;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      text = ((m['text'] ?? m['partial'] ?? '') as String).toLowerCase().trim();
    } catch (_) {
      return false;
    }
    if (RegExp(r'\b(?:hey|hi)\s+doc\s+sync\b').hasMatch(text)) return true;
    return text == 'doc sync';
  }

  @override
  void dispose() {
    final rec = _rec;
    _rec = null;
    unawaited(_chain.then((_) => rec?.dispose()));
  }
}

/// The wake engine the app uses: Vosk listening for the phrase, or none (null from [init]) when
/// the Vosk model is not available. Kept as the one seam where another engine would plug in.
class AutoWakeWordEngine implements WakeWordEngine {
  WakeWordEngine? _inner;

  @override
  Future<WakeModel?> init() async {
    if (_inner != null) return _inner!.init();
    final vosk = VoskWakeWordEngine();
    final m = await vosk.init();
    if (m != null) _inner = vosk;
    return m;
  }

  @override
  double process(Int16List frame) => _inner?.process(frame) ?? 0;

  @override
  void dispose() {
    _inner?.dispose();
    _inner = null;
  }
}

/// Speech-to-text on the phone (Vosk) instead of the server's Sarvam recogniser. Replies can
/// still be synthesised by the server when the user turns the phone voice off, so everything
/// but [transcribe] is inherited.
class OnDeviceSpeechRepository extends SpeechRepository {
  OnDeviceSpeechRepository(super.api);

  static const _wavHeader = 44; // pcm16ToWav writes a plain 44-byte RIFF header

  @override
  Future<Transcript> transcribe(Uint8List wav, {String? lang, CancelToken? cancel}) async {
    final pcm = wav.length > _wavHeader ? Uint8List.sublistView(wav, _wavHeader) : Uint8List(0);
    if (pcm.isEmpty) throw SpeechException(SpeechError.noAudio);
    final Recognizer rec;
    try {
      rec = await VoskModels.instance.recognizer();
    } catch (_) {
      // No model in this build (or it failed to load): the server recogniser hears it instead,
      // so dictation and voice keep working. Settings says so next to the switch.
      return super.transcribe(wav, lang: lang, cancel: cancel);
    }
    try {
      const chunk = 8000; // 0.25 s
      for (var pos = 0; pos < pcm.length; pos += chunk) {
        final end = pos + chunk < pcm.length ? pos + chunk : pcm.length;
        await rec.acceptWaveformBytes(Uint8List.sublistView(pcm, pos, end));
      }
      return Transcript(textOf(await rec.getFinalResult()), 'en-IN');
    } finally {
      await rec.dispose();
    }
  }

  /// The words of a final Vosk result, `{"text": "…"}`.
  static String textOf(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return ((m['text'] ?? '') as String).trim();
    } catch (_) {
      return '';
    }
  }
}
