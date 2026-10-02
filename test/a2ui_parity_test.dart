// The app half of this round's server work, tested against the same shapes the web glue checks
// in web/actions.mjs (server repo): Preview (M3), "Enter information" (M4), several keyed confirm
// cards in one reply (M5), and the look ported from ai-a2ui.css.
//
// The pure ports (toneFor, previewRequest, formRequest, proposalKey) MUST agree with
// web/src/a2ui-docsync.js — two renderers of one surface deciding differently is the bug these
// pins exist to catch. The controller cases drive the REAL ChatController through a scripted
// repository.
//
// Run: flutter test test/a2ui_parity_test.dart

import 'dart:convert';

import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/chat/controller/commit_ledger.dart';
import 'package:docsync_app/features/chat/model/a2ui_actions.dart';
import 'package:docsync_app/features/chat/model/a2ui_tone.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:docsync_app/features/chat/view/widgets/fix_form_sheet.dart';
import 'package:docsync_app/features/voice/model/voice_choices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_chat_repository.dart';

void main() {
  group('the status tone (web toneFor)', () {
    test('reads the word, not its case or punctuation', () {
      expect(toneFor('Overdue'), 'danger');
      expect(toneFor('UNPAID!'), 'danger');
      expect(toneFor('On hold'), 'warn');
      expect(toneFor('Partially paid'), 'warn');
      expect(toneFor('Completed'), 'success');
      expect(toneFor('Paid'), 'success');
      expect(toneFor('Pending'), 'info');
      expect(toneFor('In progress'), 'info');
      expect(toneFor('Draft'), 'neutral');
      expect(toneFor(''), 'neutral');
      expect(toneFor(null), 'neutral');
    });

    test('danger wins over the rest, as on the web', () {
      expect(toneFor('Completed but overdue'), 'danger');
    });

    test('the expander label and the kind', () {
      expect(moreLabel(22, false), 'Show 22 more');
      expect(moreLabel(-3, false), 'Show 0 more');
      expect(moreLabel(22, true), 'Show fewer');
      expect(surfaceKind('confirm_create_invoice_32c987d9'), 'confirm');
      expect(surfaceKind('list'), 'list');
      expect(isHighPriority('High priority · due 25 Sep 2026'), isTrue);
      expect(isHighPriority('Client: Acme · urgent priority'), isTrue);
      expect(isHighPriority('Low priority'), isFalse);
    });
  });

  group('Preview requests (web previewRequest)', () {
    test('a draft carries its action and args TEXT, unchanged', () {
      const args = '{"client_id":12,"task_ids":[812]}';
      final r = previewRequest({'kind': 'draft', 'action': 'create_invoice', 'args': args})!;
      expect(r.fields, {'kind': 'draft', 'action': 'create_invoice', 'args': args});
    });

    test('an invoice carries only its id', () {
      expect(previewRequest({'kind': 'invoice', 'id': 301})!.fields, {'kind': 'invoice', 'id': '301'});
      expect(previewRequest({'kind': 'invoice', 'id': ['301']}), const PreviewRequest.invoice(301));
    });

    test('anything else draws nothing', () {
      expect(previewRequest({'kind': 'invoice', 'id': 0}), isNull);
      expect(previewRequest({'kind': 'draft', 'action': 'Bad-Name', 'args': '{}'}), isNull);
      expect(previewRequest({'kind': 'draft', 'action': 'create_invoice', 'args': '[1,2]'}), isNull);
      expect(previewRequest({'kind': 'draft', 'action': 'create_invoice', 'args': '{oops'}), isNull);
      expect(previewRequest({'kind': 'page'}), isNull);
      expect(routeA2uiAction('docsync.preview', {'kind': 'x'}), isA<ActionFailed>());
    });
  });

  group('Enter information requests (web formRequest)', () {
    test('a known form with a clean id list', () {
      final r = formRequest({'form': 'task_fee', 'ids': '812,813', 'retry': '  invoice 812  '})!;
      expect(r, const FormRequest(form: 'task_fee', ids: '812,813', retry: 'invoice 812'));
    });

    test('an unknown form, a bad id list or a bad field name is refused or dropped', () {
      expect(formRequest({'form': 'client_delete', 'ids': '5'}), isNull);
      expect(formRequest({'form': 'client_contact', 'ids': '0'}), isNull);
      expect(formRequest({'form': 'client_contact', 'ids': '5;6'}), isNull);
      expect(formRequest({'form': 'client_contact', 'ids': '1,2,3,4,5,6,7,8,9,10,11'}), isNull);
      expect(formRequest({'form': 'client_contact', 'ids': '5', 'need': 'Email!'})!.need, '');
      expect(routeA2uiAction('docsync.form', {'form': 'nope', 'ids': '1'}), isA<ActionFailed>());
    });

    test('a retry question is capped at 500 characters', () {
      final r = formRequest({'form': 'client_address', 'ids': '9', 'retry': 'x' * 900})!;
      expect(r.retry.length, 500);
    });
  });

  group('keyed confirm cards (server M5)', () {
    test('a key is 8 lowercase hex characters, or nothing', () {
      expect(proposalKey('abcdef12'), 'abcdef12');
      expect(proposalKey(['abcdef12']), 'abcdef12');
      expect(proposalKey('ABCDEF12'), '');
      expect(proposalKey('abc'), '');
      expect(proposalKey(null), '');
      expect(confirmSurfaceId('create_invoice', ''), 'confirm_create_invoice');
      expect(confirmSurfaceId('create_invoice', 'abcdef12'), 'confirm_create_invoice_abcdef12');
    });

    test('commit and cancel carry the key; a forged one is dropped', () {
      final c = routeA2uiAction('docsync.commit',
          {'action': 'create_invoice', 'args': '{"task_ids":[815]}', 'key': '32c987d9'}) as CommitWrite;
      expect(c.key, '32c987d9');
      expect(routeA2uiAction('docsync.cancel', {'action': 'create_invoice', 'key': 'zz'}),
          const CancelWrite('create_invoice'));
    });

    test('the confirm event and a stored message both keep the key', () {
      final ev = RagEvent.fromJson({
        'type': 'confirm',
        'name': 'create_invoice',
        'summary': 'Invoice for task #815',
        'commit_args': {'task_ids': [815]},
        'key': '32c987d9',
      });
      expect(ev.proposal!.key, '32c987d9');

      final m = ChatMessage.fromJson({
        'role': 'assistant',
        'content': 'Two invoices.',
        'meta': {
          'confirm': {'name': 'create_invoice', 'commit_args': {'task_ids': [812]}, 'key': 'aaaaaaaa'},
          'confirms': [
            {'name': 'create_invoice', 'commit_args': {'task_ids': [812]}, 'key': 'aaaaaaaa'},
            {'name': 'create_invoice', 'commit_args': {'task_ids': [815]}, 'key': 'bbbbbbbb'},
          ],
        },
      });
      expect(m.confirms.map((p) => p.key), ['aaaaaaaa', 'bbbbbbbb']);
      expect(m.confirm!.key, 'aaaaaaaa');
      expect(confirmsOf(m).map((c) => c.surfaceId),
          ['confirm_create_invoice_aaaaaaaa', 'confirm_create_invoice_bbbbbbbb']);
    });

    test('an older stored message (meta.confirm only) still has its one card', () {
      final m = ChatMessage.fromJson({
        'role': 'assistant',
        'meta': {
          'confirm': {'name': 'add_todo', 'commit_args': {'title': 'x'}},
        },
      });
      expect(m.confirms, hasLength(1));
      expect(confirmOf(m)!.key, '');
    });

    test('the controller keeps EVERY confirm of a turn, the first staying `confirm`', () async {
      final repo = ScriptedChatRepository(const [
        {'type': 'conversation', 'id': 42},
        {'type': 'token', 'text': '**1.** Invoice task 812\n'},
        {'type': 'confirm', 'name': 'create_invoice', 'summary': 'Invoice for #812',
         'commit_args': {'task_ids': [812]}, 'key': 'aaaaaaaa'},
        {'type': 'token', 'text': '**2.** Invoice task 815\n'},
        {'type': 'confirm', 'name': 'create_invoice', 'summary': 'Invoice for #815',
         'commit_args': {'task_ids': [815]}, 'key': 'bbbbbbbb'},
        {'type': 'final', 'answer': 'Two cards.', 'elapsed': 1.0},
      ]);
      final container = ProviderContainer(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await container.read(chatControllerProvider.notifier).send('invoice 812 and invoice 815');
      final last = container.read(chatControllerProvider).messages.last;
      expect(last.confirms.map((p) => p.summary), ['Invoice for #812', 'Invoice for #815']);
      expect(last.confirm!.summary, 'Invoice for #812');
    });

    testWidgets('Enter information: schema, a required check, then the save posts only to ai_fix.php',
        (tester) async {
      final repo = ScriptedChatRepository(const [])
        ..fixReply = (f) => f['op'] == 'schema'
            ? {
                'ok': true,
                'title': 'Contact details - Acme Traders',
                'fields': [
                  {'name': 'email', 'label': 'Email', 'type': 'email', 'required': true},
                  {'name': 'pan', 'label': 'PAN', 'type': 'text', 'on_file': true, 'upper': true},
                ],
                'submit': 'Save',
              }
            : {'ok': true, 'message': 'Saved the email for Acme Traders.'};
      String? saved = 'not yet';
      await tester.pumpWidget(ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => saved = await FixFormSheet.show(context,
                    const FormRequest(form: 'client_contact', ids: '2144', need: 'email')),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Contact details - Acme Traders'), findsOneWidget);
      expect(find.text('on file'), findsOneWidget);
      expect(repo.fixes.single, {'op': 'schema', 'form': 'client_contact', 'ids': '2144', 'need': 'email'});

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('This is needed.'), findsOneWidget);
      expect(repo.fixes, hasLength(1), reason: 'an empty required field is not posted');

      await tester.enterText(find.byType(TextField).first, 'accounts@acme.in');
      await tester.pump();
      expect(find.text('This is needed.'), findsNothing, reason: 'typing clears the field error');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.fixes.last['op'], 'save');
      expect(repo.fixes.last['email'], 'accounts@acme.in');
      expect(repo.fixes.last['pan'], '', reason: 'a field on file left empty stays as it is');
      expect(saved, 'Saved the email for Acme Traders.');
      expect(repo.asked, isEmpty, reason: 'the value never goes through the chat');
    });

    test('the second card commits ITS args with ITS key; the first is left alone', () async {
      final repo = ScriptedChatRepository(const []);
      final container = ProviderContainer(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final ledger = container.read(commitLedgerProvider.notifier);
      final res = await ledger.commit(42, 'create_invoice', {'task_ids': [815]}, proposalKey: 'bbbbbbbb');
      expect(res.ok, isTrue);
      expect(repo.commits.single.key, 'bbbbbbbb');
      expect(jsonEncode(repo.commits.single.args), '{"task_ids":[815]}');
      expect(ledger.entry(42, 'create_invoice', {'task_ids': [812]}), isNull,
          reason: 'the other card is still open');
    });
  });
}
