import 'dart:typed_data';

import 'package:docsync_app/features/voice/model/vosk_speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the Vosk wake phrase', () {
    test('"hey doc sync" wakes it, final or partial', () {
      expect(VoskWakeWordEngine.heard('{"text": "hey doc sync"}'), isTrue);
      expect(VoskWakeWordEngine.heard('{"partial": "hey doc sync"}'), isTrue);
      expect(VoskWakeWordEngine.heard('{"partial": "[unk] hi doc sync"}'), isTrue);
    });

    test('"doc sync" alone wakes it only as a whole utterance', () {
      expect(VoskWakeWordEngine.heard('{"text": "doc sync"}'), isTrue);
      expect(VoskWakeWordEngine.heard('{"partial": "doc sync"}'), isTrue);
      expect(VoskWakeWordEngine.heard('{"text": "[unk] doc sync [unk]"}'), isFalse);
    });

    test('anything else does not', () {
      expect(VoskWakeWordEngine.heard('{"partial": ""}'), isFalse);
      expect(VoskWakeWordEngine.heard('{"text": "[unk]"}'), isFalse);
      expect(VoskWakeWordEngine.heard('{"text": "hey doc"}'), isFalse);
      expect(VoskWakeWordEngine.heard('not json'), isFalse);
    });

    test('the grammar spells the phrase in words the model knows', () {
      expect(VoskWakeWordEngine.grammar, contains('hey doc sync'));
      expect(VoskWakeWordEngine.grammar, contains('[unk]'));
      expect(VoskWakeWordEngine.grammar.any((g) => g.contains('docsync')), isFalse);
    });
  });

  group('without the bundled model (the APK-size build)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('the build reports the offline model as missing', () async {
      expect(await VoskModels.instance.bundled(), isFalse);
    });

    test('the wake engine is simply unavailable, never an error', () async {
      final engine = AutoWakeWordEngine();
      expect(await engine.init(), isNull);
      expect(engine.process(Int16List(1280)), 0);
      engine.dispose();
    });
  });

  test('a final transcript is the text, trimmed', () {
    expect(OnDeviceSpeechRepository.textOf('{"text" : " pending tasks "}'), 'pending tasks');
    expect(OnDeviceSpeechRepository.textOf('{"text": ""}'), '');
    expect(OnDeviceSpeechRepository.textOf('garbage'), '');
  });
}
