// A spoken CONVERSATION through the REAL VoiceSession, ChatController and CommitLedger, with
// the mic, the speech server and the speaker faked.

import 'dart:convert';
import 'dart:io';

import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/chat/controller/commit_ledger.dart';
import 'package:docsync_app/features/voice/controller/voice_session.dart';
import 'package:docsync_app/features/voice/model/speech_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/voice_fakes.dart';

const answer = <Map<String, dynamic>>[
  {'type': 'conversation', 'id': 5, 'turn': 1},
  {'type': 'token', 'text': 'Theek hai, kal subah 11 baje ka reminder set kar diya hai. '},
  {'type': 'token', 'text': 'Amit Traders ko call karna hai.'},
  {'type': 'final', 'answer': 'Theek hai, kal subah 11 baje ka reminder set kar diya hai. Amit Traders ko call karna hai.'},
];

List<Map<String, dynamic>> confirmTurn(String name, Map<String, dynamic> args, String summary) => [
      {'type': 'conversation', 'id': 6, 'turn': 1},
      {'type': 'confirm', 'name': name, 'summary': summary, 'commit_args': args},
    ];

/// A turn that asks "Which Acme did you mean?" with the picker surface the server composes.
List<Map<String, dynamic>> pickerTurn() {
  final fixtures = jsonDecode(File('test/fixtures/surfaces.json').readAsStringSync()) as Map;
  return [
    {'type': 'conversation', 'id': 7, 'turn': 1},
    {'type': 'token', 'text': 'Which Acme did you mean?'},
    for (final m in fixtures['picker'] as List) {'type': 'a2ui', 'msg': m},
    {'type': 'final', 'answer': 'Which Acme did you mean?'},
  ];
}

void main() {
  group('one exchange', () {
    test('speak → heard → asked as a voice turn → spoken sentence by sentence', () async {
      final h = await voiceHarness(
          script: answer, mic: [utterance()], transcripts: ['kal 11 baje Amit ko call yaad dilana']);
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);

      expect(h.speech.heard, hasLength(1));
      expect(h.speech.heard.single.bytes, greaterThan(44), reason: 'a WAV with samples in it');
      expect(h.mic.running, isFalse, reason: 'the mic is closed once the utterance ends');
      expect(h.chat.asked, ['kal 11 baje Amit ko call yaad dilana']);
      expect(h.chat.voiceFlags.single, (voice: true, lang: 'hi-IN'));
      expect(h.speech.spoken, [
        'Theek hai, kal subah 11 baje ka reminder set kar diya hai.',
        'Amit Traders ko call karna hai.',
      ]);
      expect(h.c.read(voiceSessionProvider).phase, VoicePhase.idle);
    });

    test('silence is "I didn\'t hear anything", and nothing is sent anywhere', () async {
      final h = await voiceHarness(script: answer, mic: [silence()]);
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.speech.heard, isEmpty);
      expect(h.chat.asked, isEmpty);
      expect(h.c.read(voiceSessionProvider).note, contains('didn\'t hear'));
    });

    test('no mic permission says so', () async {
      final h = await voiceHarness(script: answer, permitted: false);
      await h.c.read(voiceSessionProvider.notifier).listen();
      expect(h.mic.starts, 0);
      expect(h.c.read(voiceSessionProvider).note, contains('microphone'));
    });

    test('out of speech credits is reported, and the question is not guessed at', () async {
      final h = await voiceHarness(
          script: answer, mic: [utterance()], sttFails: SpeechException(SpeechError.quota));
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.chat.asked, isEmpty);
      expect(h.c.read(voiceSessionProvider).note, contains('out of credits'));
    });
  });

  group('follow-up', () {
    test('after the reply it keeps listening, and a follow-up is a second turn', () async {
      final h = await voiceHarness(
        script: answer,
        followUp: true,
        mic: [utterance(), utterance(), silence()],
        transcripts: ['reminder lagao', 'aur kya pending hai'],
      );
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.chat.asked, ['reminder lagao', 'aur kya pending hai']);
      expect(h.c.read(voiceSessionProvider).phase, VoicePhase.idle);
      expect(h.c.read(voiceSessionProvider).note, isNull, reason: 'a quiet ending is not an error');
    });

    test('"stop" in the follow-up window ends it without a turn', () async {
      final h = await voiceHarness(
        script: answer,
        followUp: true,
        mic: [utterance(), utterance()],
        transcripts: ['reminder lagao', 'bas'],
      );
      await h.c.read(voiceSessionProvider.notifier).listen();
      await settle(h.c);
      expect(h.chat.asked, ['reminder lagao']);
    });
  });

  group('spoken confirm', () {
    const args = {'task_creation_id': 581, 'status': 'completed'};

    test('"haan kar do" commits once, through the ledger', () async {
      final h = await voiceHarness(
        script: confirmTurn('set_task_status', args, 'Move task #581 to completed.'),
        mic: [utterance()],
        transcripts: ['haan kar do'],
      );
      await h.c.read(voiceSessionProvider.notifier).ask('task 581 complete karo');
      await settle(h.c);
      expect(h.speech.spoken.first, 'Move task #581 to completed. Shall I go ahead?');
      expect(h.chat.commits, hasLength(1));
      expect(h.chat.commits.single.action, 'set_task_status');
      expect(h.chat.commits.single.args, args);
      expect(h.speech.spoken.last, 'Done.');
      // And the on-screen Confirm cannot write it again.
      final again =
          await h.c.read(commitLedgerProvider.notifier).commit(6, 'set_task_status', args);
      expect(again.ok, isFalse);
      expect(h.chat.commits, hasLength(1));
    });

    test('"nahi" cancels, and a later tap cannot resurrect it', () async {
      final h = await voiceHarness(
        script: confirmTurn('set_task_status', args, 'Move task #581 to completed.'),
        mic: [utterance()],
        transcripts: ['nahi'],
      );
      await h.c.read(voiceSessionProvider.notifier).ask('task 581 complete karo');
      await settle(h.c);
      expect(h.chat.commits, isEmpty);
      expect(h.speech.spoken.last, 'Okay, cancelled.');
      final tap = await h.c.read(commitLedgerProvider.notifier).commit(6, 'set_task_status', args);
      expect(tap.ok, isFalse);
      expect(h.chat.commits, isEmpty);
    });

    test('an unclear reply is asked again, never guessed', () async {
      final h = await voiceHarness(
        script: confirmTurn('set_task_status', args, 'Move task #581 to completed.'),
        mic: [utterance(), utterance()],
        transcripts: ['haan nahi', 'yes'],
      );
      await h.c.read(voiceSessionProvider.notifier).ask('task 581 complete karo');
      await settle(h.c);
      expect(h.speech.spoken, contains('Sorry, was that a yes or a no?'));
      expect(h.chat.commits, hasLength(1));
    });

    test('a new request instead of yes/no leaves the card alone and is asked', () async {
      final h = await voiceHarness(
        script: confirmTurn('set_task_status', args, 'Move task #581 to completed.'),
        mic: [utterance()],
        transcripts: ['pehle mujhe Amit Traders ke saare pending tasks dikhao please'],
      );
      await h.c.read(voiceSessionProvider.notifier).ask('task 581 complete karo');
      await settle(h.c);
      expect(h.chat.commits, isEmpty);
      expect(h.chat.asked.last, 'pehle mujhe Amit Traders ke saare pending tasks dikhao please');
    });

    group('outbound (to the client)', () {
      const send = {'invoice_main_id': 65, 'to': 'client', 'channel': 'email'};

      test('yes, then "cancel" in the 3-second window: nothing is sent', () async {
        final h = await voiceHarness(
          script: confirmTurn('send_invoice', send, 'Email invoice #65 to Amit Traders.'),
          mic: [utterance(), utterance()],
          transcripts: ['yes', 'cancel'],
        );
        await h.c.read(voiceSessionProvider.notifier).ask('invoice 65 bhej do');
        await settle(h.c);
        expect(h.speech.spoken, contains('Sending in three seconds. Say cancel to stop.'));
        expect(h.chat.commits, isEmpty);
        expect(h.speech.spoken.last, 'Okay, I haven\'t sent it.');
      });

      test('yes, then silence: it is sent', () async {
        final h = await voiceHarness(
          script: confirmTurn('send_invoice', send, 'Email invoice #65 to Amit Traders.'),
          mic: [utterance(), silence()],
          transcripts: ['haan bhej do'],
        );
        await h.c.read(voiceSessionProvider.notifier).ask('invoice 65 bhej do');
        await settle(h.c);
        expect(h.chat.commits.single.action, 'send_invoice');
      });

      test('to "me" is not outbound: no cancel window', () async {
        final h = await voiceHarness(
          script: confirmTurn('send_invoice', {...send, 'to': 'me'}, 'Email invoice #65 to you.'),
          mic: [utterance()],
          transcripts: ['yes'],
        );
        await h.c.read(voiceSessionProvider.notifier).ask('invoice mujhe bhejo');
        await settle(h.c);
        expect(h.speech.spoken, isNot(contains('Sending in three seconds. Say cancel to stop.')));
        expect(h.chat.commits, hasLength(1));
      });
    });
  });

  group('spoken picker', () {
    test('the options are read out and "doosra wala" sends what tapping the second sends',
        () async {
      final h = await voiceHarness(script: pickerTurn(), mic: [utterance()], transcripts: ['doosra wala']);
      await h.c.read(voiceSessionProvider.notifier).ask('Acme ka status');
      await settle(h.c);
      expect(h.speech.spoken.any((s) => s.contains('Second, Acme Exports.')), isTrue);
      expect(h.chat.asked[1], 'Use client #2145 — Acme Exports.');
    });

    test('a name works too', () async {
      final h = await voiceHarness(
          script: pickerTurn(), mic: [utterance()], transcripts: ['Acme Holdings']);
      await h.c.read(voiceSessionProvider.notifier).ask('Acme ka status');
      await settle(h.c);
      expect(h.chat.asked[1], 'Use client #2146 — Acme Holdings.');
    });
  });

  group('interrupting', () {
    test('talking over the reply stops it; "ruko" ends the conversation', () async {
      final h = await voiceHarness(
        script: answer,
        bargeIn: true,
        holdPlayback: true,
        mic: [utterance()], // heard by the barge-in listener while it talks
        transcripts: ['ruko'],
      );
      await h.c.read(voiceSessionProvider.notifier).ask('status batao');
      await settle(h.c);
      expect(h.player.stops, greaterThan(0));
      expect(h.chat.asked, ['status batao']);
      expect(h.c.read(voiceSessionProvider).phase, VoicePhase.idle);
    });

    test('talking over it with a question asks that question next', () async {
      final h = await voiceHarness(
        script: answer,
        bargeIn: true,
        holdPlayback: true,
        mic: [utterance()],
        transcripts: ['aur GST ka kya hua'],
      );
      await h.c.read(voiceSessionProvider.notifier).ask('status batao');
      await settle(h.c);
      expect(h.chat.asked.take(2), ['status batao', 'aur GST ka kya hua']);
    });

    test('a tap while it talks stops the conversation', () async {
      final h = await voiceHarness(script: answer, holdPlayback: true);
      final session = h.c.read(voiceSessionProvider.notifier);
      final run = session.ask('status batao');
      for (var i = 0; i < 200 && h.c.read(voiceSessionProvider).phase != VoicePhase.speaking; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.c.read(voiceSessionProvider).phase, VoicePhase.speaking);
      await session.tap();
      await run;
      await settle(h.c);
      expect(h.c.read(voiceSessionProvider).phase, VoicePhase.idle);
      expect(h.chat.asked, ['status batao']);
    });
  });

  test('leaving the screen releases the mic mid-question', () async {
    final h = await voiceHarness(script: answer, mic: [silence()]);
    final session = h.c.read(voiceSessionProvider.notifier);
    final run = session.listen();
    for (var i = 0; i < 50 && !h.mic.running; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(h.mic.running, isTrue);
    await session.cancel();
    await run;
    expect(h.mic.running, isFalse);
    expect(h.chat.asked, isEmpty);
    expect(h.c.read(chatControllerProvider).sending, isFalse);
  });
}
