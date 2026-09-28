// The rules behind a spoken answer: what counts as yes/no/stop, which option was named, and
// that every surface the server composes is read into exactly the action a tap produces.

import 'dart:convert';
import 'dart:io';

import 'package:docsync_app/features/chat/model/a2ui_actions.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:docsync_app/features/voice/controller/voice_session.dart';
import 'package:docsync_app/features/voice/controller/wake_word.dart';
import 'package:docsync_app/features/voice/model/intent_lexicon.dart';
import 'package:docsync_app/features/voice/model/voice_choices.dart';
import 'package:docsync_app/features/voice/model/voice_picker_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/voice_fakes.dart';

ChatMessage withSurface(String key) {
  final fixtures = jsonDecode(File('test/fixtures/surfaces.json').readAsStringSync()) as Map;
  return ChatMessage(
    role: 'assistant',
    a2ui: [for (final m in fixtures[key] as List) Map<String, dynamic>.from(m as Map)],
  );
}

void main() {
  group('yes / no / stop', () {
    for (final s in ['yes', 'Yes, go ahead.', 'haan', 'haan ji', 'theek hai kar do', 'हाँ', 'ठीक है', 'bhej do', 'ok']) {
      test('"$s" is yes', () => expect(classifyReply(s), ReplyIntent.yes));
    }
    for (final s in ['no', 'nahi', 'nahin', 'mat bhejo', 'cancel', 'नहीं', 'rehne do', "don't"]) {
      test('"$s" is no', () => expect(classifyReply(s), ReplyIntent.no));
    }
    for (final s in ['stop', 'ruko', 'bas', 'रुको', 'wait']) {
      test('"$s" is stop', () => expect(classifyReply(s), ReplyIntent.stop));
    }
    test('yes AND no is never a yes', () {
      expect(classifyReply('haan nahi'), ReplyIntent.unclear);
      expect(classifyReply('yes but don\'t send it'), ReplyIntent.unclear);
    });
    test('a long sentence is a new request, even with "yes" in it', () {
      expect(classifyReply('yes and also show me all the pending GST filings for March'),
          ReplyIntent.other);
    });
    test('"ha" does not match inside other words', () {
      expect(classifyReply('chahiye'), ReplyIntent.other);
      expect(classifyReply('kya hai'), ReplyIntent.other);
    });
    test('stop commands while it talks', () {
      expect(isStopCommand('ruko'), isTrue);
      expect(isStopCommand('bas karo'), isTrue);
      expect(isStopCommand('stop reminding me about GST'), isFalse);
    });
  });

  group('which option', () {
    const clients = ['Acme Traders — file_no 1201', 'Acme Exports', 'Acme Holdings — Retail group'];
    test('ordinals in English and Hindi', () {
      expect(matchOption('the first one', clients), 0);
      expect(matchOption('doosra wala', clients), 1);
      expect(matchOption('तीसरा', clients), 2);
      expect(matchOption('last', clients), 2);
      expect(matchOption('number 2', clients), 1);
      expect(matchOption('3', clients), 2);
    });
    test('by name, ignoring what every option shares', () {
      expect(matchOption('Acme Exports', clients), 1);
      expect(matchOption('holdings wala', clients), 2);
      expect(matchOption('traders', clients), 0);
    });
    test('ambiguous or out of range is null, never a guess', () {
      expect(matchOption('Acme', clients), isNull);
      expect(matchOption('fifth', clients), isNull);
      expect(matchOption('number 9', clients), isNull);
      expect(matchOption('first or second', clients), isNull);
      expect(matchOption('tomorrow at 5', clients), isNull);
    });
    test('"do" (two) inside a longer sentence is not an ordinal', () {
      expect(matchOption('do it tomorrow for Acme Exports', clients), 1);
    });
    test('status values', () {
      expect(matchOption('completed', ['Allotted', 'Checking', 'Completed']), 2);
      expect(matchOption('checking mein daalo', ['Allotted', 'Checking', 'Completed']), 1);
    });
  });

  group('reading the surfaces the server composes', () {
    test('picker: each option is the sentence the tap sends', () {
      final ch = choicesOf(withSurface('picker'))!;
      expect(ch.question, 'Which Acme did you mean?');
      expect(ch.options.map((o) => o.label), [
        'Acme Traders — file_no 1201',
        'Acme Exports',
        'Acme Holdings — Retail group',
      ]);
      expect(ch.options[1].action, const SendChat('Use client #2145 — Acme Exports.'));
    });

    test('fixed-value choice', () {
      final ch = choicesOf(withSurface('choice'))!;
      expect(ch.options.last.action, const SendChat('Use status: completed.'));
    });

    test('next-step chips and undo are options too', () {
      expect(choicesOf(withSurface('next_steps'))!.options.map((o) => describeAction(o.action)),
          ['send: Use next: email invoice #65.', 'send: Use next: mark invoice #65 paid.']);
      expect(choicesOf(withSurface('undo'))!.options.single.action,
          const SendChat('Use undo: to-do #77.'));
    });

    test('confirm surface: the exact commit and its summary', () {
      final c = confirmOf(withSurface('confirm'))!;
      expect(c.name, 'set_task_status');
      expect(c.args, {'task_creation_id': 581, 'status': 'completed', 'remark': 'done'});
      expect(c.summary, 'Move task #581 to completed.');
      expect(c.warnings, contains('This notifies the person who allotted it.'));
      expect(c.outbound, isFalse);
      expect(choicesOf(withSurface('confirm')), isNull, reason: 'Confirm/Cancel are not "options"');
    });

    test('outbound is send_invoice / chase to the CLIENT only', () {
      const base = VoiceConfirm(name: 'send_invoice', args: {'to': 'client'}, summary: '');
      expect(base.outbound, isTrue);
      expect(const VoiceConfirm(name: 'send_invoice', args: {'to': 'me'}, summary: '').outbound, isFalse);
      expect(const VoiceConfirm(name: 'chase_missing_documents', args: {'to': 'client'}, summary: '').outbound,
          isTrue);
      expect(const VoiceConfirm(name: 'mark_invoice_paid', args: {'to': 'client'}, summary: '').outbound,
          isFalse);
    });

    test('every fixture reads without throwing', () {
      final fixtures = jsonDecode(File('test/fixtures/surfaces.json').readAsStringSync()) as Map;
      for (final key in fixtures.keys) {
        final m = withSurface(key as String);
        expect(() => choicesOf(m), returnsNormally, reason: key);
        expect(() => confirmOf(m), returnsNormally, reason: key);
      }
    });
  });

  group('wake word', () {
    test('sensitivity maps to a threshold, more sensitive is lower', () {
      expect(WakeWordController.thresholdFor(0.5), closeTo(0.5, 1e-9));
      expect(WakeWordController.thresholdFor(1), lessThan(WakeWordController.thresholdFor(0)));
      expect(WakeWordController.thresholdFor(9), WakeWordController.thresholdFor(1));
    });

    test('off in settings: nothing listens', () async {
      final h = await voiceHarness(script: const [], wakeWord: false);
      expect(h.c.read(wakeWordProvider).status, WakeWordStatus.off);
      await Future<void>.delayed(Duration.zero);
      expect(h.mic.starts, 0);
    });

    test('on: it listens, and the phrase hands the mic to a voice session', () async {
      // Detect only after the warm-up, as the engine would.
      final engine = FakeWakeEngine(fromFrame: WakeWordController.warmupFrames + 1);
      final h = await voiceHarness(
        script: const [
          {'type': 'final', 'answer': 'Okay.'}
        ],
        wakeWord: true,
        wake: engine,
        mic: [
          [tone(4000, 0.1)], // the wake listener's audio: ~50 frames
          utterance(), // the question after the wake word
        ],
        transcripts: ['GST status batao'],
      );
      h.c.listen(wakeWordProvider, (_, _) {});
      for (var i = 0; i < 20000 && h.chat.asked.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(engine.inits, 1);
      expect(h.chat.asked, ['GST status batao']);
      await settle(h.c);
      // Back to listening for the phrase once the conversation is over.
      for (var i = 0; i < 200 && h.c.read(wakeWordProvider).status != WakeWordStatus.listening; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.c.read(wakeWordProvider).status, WakeWordStatus.listening);
      expect(h.c.read(voiceSessionProvider).phase, VoicePhase.idle);
    });

    test('not on the Voice tab (or app in background): paused, mic released', () async {
      final h = await voiceHarness(script: const [], wakeWord: true, mic: [silence(), silence()]);
      h.c.listen(wakeWordProvider, (_, _) {});
      for (var i = 0; i < 200 && h.c.read(wakeWordProvider).status != WakeWordStatus.listening; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.mic.running, isTrue);
      h.c.read(voiceForegroundProvider.notifier).setTabVisible(false);
      for (var i = 0; i < 50 && h.mic.running; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.c.read(wakeWordProvider).status, WakeWordStatus.paused);
      expect(h.mic.running, isFalse);
    });

    test('an engine that cannot start is reported, not retried forever', () async {
      final engine = FakeWakeEngine(available: false);
      final h = await voiceHarness(script: const [], wakeWord: true, wake: engine);
      h.c.listen(wakeWordProvider, (_, _) {});
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.c.read(wakeWordProvider).status, WakeWordStatus.unavailable);
      h.c.read(voiceForegroundProvider.notifier).setTabVisible(false);
      h.c.read(voiceForegroundProvider.notifier).setTabVisible(true);
      await Future<void>.delayed(Duration.zero);
      expect(engine.inits, 1);
    });
  });
}
