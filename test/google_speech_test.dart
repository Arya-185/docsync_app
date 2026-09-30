// Listening through the phone's Google recogniser: the voice session and dictation use it when
// it is there, and fall back to recording + the server recogniser when it is not.

import 'dart:ui' show Locale;

import 'package:docsync_app/features/voice/controller/dictation.dart';
import 'package:docsync_app/features/voice/controller/voice_session.dart';
import 'package:docsync_app/features/voice/model/google_speech.dart';
import 'package:docsync_app/features/voice/model/speech_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/voice_fakes.dart';

const answer = <Map<String, dynamic>>[
  {'type': 'conversation', 'id': 5, 'turn': 1},
  {'type': 'token', 'text': 'You have 3 pending tasks.'},
  {'type': 'final', 'answer': 'You have 3 pending tasks.'},
];

void main() {
  group('the voice screen', () {
    test('what Google hears is asked; the recorder and the server recogniser are not used',
        () async {
      final live = FakeLive(['pending tasks for Ahana Enterprises']);
      final h = await voiceHarness(script: answer, live: live);
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);

      expect(h.chat.asked, ['pending tasks for Ahana Enterprises']);
      expect(h.mic.starts, 0, reason: 'Google opens its own mic');
      expect(h.speech.heard, isEmpty, reason: 'nothing is sent to the server recogniser');
      expect(h.chat.voiceFlags.single, (voice: true, lang: 'en-IN'));
      expect(h.speech.spoken, ['You have 3 pending tasks.']);
    });

    test('the follow-up window is the session\'s, not the recogniser\'s default', () async {
      final live = FakeLive(['pending tasks', '']);
      final h = await voiceHarness(script: answer, live: live, followUp: true);
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(live.listens, hasLength(2));
      expect(live.listens[1].noSpeech, const Duration(milliseconds: VoiceSession.followUpMs));
      expect(h.chat.asked, ['pending tasks'], reason: 'silence in the window ends it quietly');
      expect(h.c.read(voiceSessionProvider).note, isNull);
    });

    test('nothing heard is "I didn\'t hear anything"', () async {
      final h = await voiceHarness(script: answer, live: FakeLive(['']));
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.chat.asked, isEmpty);
      expect(h.c.read(voiceSessionProvider).note, contains('didn\'t hear'));
    });

    test('a broken recogniser hands the utterance to the recorder and the server', () async {
      final h = await voiceHarness(
        script: answer,
        live: FakeLive([SpeechException(SpeechError.recognizer, 'error_client')]),
        mic: [utterance()],
        transcripts: ['pending tasks'],
      );
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.mic.starts, 1);
      expect(h.speech.heard, hasLength(1));
      expect(h.chat.asked, ['pending tasks']);
    });

    test('a network failure is reported, not guessed at or re-recorded', () async {
      final h = await voiceHarness(
          script: answer, live: FakeLive([SpeechException(SpeechError.failed, 'error_network')]));
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.chat.asked, isEmpty);
      expect(h.mic.starts, 0);
      expect(h.c.read(voiceSessionProvider).note, contains('didn\'t go through'));
    });

    test('no Google on the phone: the recorder path, as before', () async {
      final h = await voiceHarness(
        script: answer,
        live: FakeLive(const [], isAvailable: false),
        mic: [utterance()],
        transcripts: ['pending tasks'],
      );
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.speech.heard, hasLength(1));
      expect(h.chat.asked, ['pending tasks']);
    });
  });

  group('dictation', () {
    test('the words so far are reported, then the final text', () async {
      final h = await voiceHarness(script: answer, live: FakeLive(['unpaid invoices']));
      final partials = <String>[];
      final text = await h.c.read(dictationProvider).run(onPartial: partials.add);
      expect(text, 'unpaid invoices');
      expect(partials, ['unpaid']);
      expect(h.speech.heard, isEmpty);
    });

    test('a broken recogniser falls back to recording + the server', () async {
      final h = await voiceHarness(
        script: answer,
        live: FakeLive([SpeechException(SpeechError.recognizer, 'error_busy')]),
        mic: [utterance()],
        transcripts: ['unpaid invoices'],
      );
      expect(await h.c.read(dictationProvider).run(), 'unpaid invoices');
      expect(h.speech.heard, hasLength(1));
    });
  });

  group('GoogleSpeechRecognizer rules', () {
    test('the language: Settings first, then an Indian phone locale, else en-IN', () {
      expect(GoogleSpeechRecognizer.localeFor('hi-IN', const Locale('en', 'US')), 'hi-IN');
      expect(GoogleSpeechRecognizer.localeFor(null, const Locale('hi', 'IN')), 'hi-IN');
      expect(GoogleSpeechRecognizer.localeFor(null, const Locale('en', 'IN')), 'en-IN');
      expect(GoogleSpeechRecognizer.localeFor(null, const Locale('en', 'US')), 'en-IN');
      expect(GoogleSpeechRecognizer.localeFor(null, const Locale('ta', 'IN')), 'en-IN');
    });

    test('loudness in dB becomes 0..1', () {
      expect(GoogleSpeechRecognizer.levelOf(-10), 0);
      expect(GoogleSpeechRecognizer.levelOf(4), closeTo(0.5, 1e-9));
      expect(GoogleSpeechRecognizer.levelOf(20), 1);
    });

    test('errors: silence is not an error; network is retryable; the rest mean "use another"',
        () {
      expect(GoogleSpeechRecognizer.errorFor('error_no_match'), isNull);
      expect(GoogleSpeechRecognizer.errorFor('error_speech_timeout'), isNull);
      expect(GoogleSpeechRecognizer.errorFor('error_permission'), SpeechError.noAudio);
      expect(GoogleSpeechRecognizer.errorFor('error_network'), SpeechError.failed);
      expect(GoogleSpeechRecognizer.errorFor('error_server_disconnected'), SpeechError.failed);
      expect(GoogleSpeechRecognizer.errorFor('error_language_unavailable'), SpeechError.recognizer);
      expect(GoogleSpeechRecognizer.errorFor('error_busy'), SpeechError.recognizer);
      expect(GoogleSpeechRecognizer.errorFor('error_unknown (13)'), SpeechError.recognizer);
    });

    test('without the plugin (tests, desktop) it is simply unavailable', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(await GoogleSpeechRecognizer.instance.available(), isFalse);
    });
  });
}
