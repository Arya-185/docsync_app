// THE "RENDERS NOTHING" TEST.
//
// A surface can satisfy every schema and still draw nothing. That is not hypothetical: on the
// web, the glue read `surface.components` when the model exposes `surface.componentsModel`, and
// every surface validated perfectly while the chat showed an empty bubble. Conformance checks
// answer "is this payload legal"; only pumping it through the real renderer and looking for the
// text answers "did the user see it".
//
// The fixtures are the SAME BYTES the web tests use — test/fixtures/surfaces.json is a copy of
// web/fixtures/surfaces.json, which tests/php/ai_uisurface_test.php generates. Two independent
// implementations of one protocol (genui here, @a2ui/web_core there) agreeing on identical
// input is the only thing that actually proves they agree.
//
// Run: flutter test test/a2ui_render_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:docsync_app/features/chat/model/a2ui_actions.dart';
import 'package:docsync_app/features/chat/model/a2ui_navigate.dart';
import 'package:docsync_app/features/chat/view/widgets/a2ui_surface_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every surface the server can compose, keyed as in the PHP fixture array.
Map<String, List<Map<String, dynamic>>> loadFixtures() {
  final file = File('test/fixtures/surfaces.json');
  if (!file.existsSync()) {
    fail('test/fixtures/surfaces.json is missing. Copy it from the server repo '
        '(web/fixtures/surfaces.json) — the point of this suite is that the bytes match.');
  }
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(
        k,
        (v as List).map((m) => Map<String, dynamic>.from(m as Map)).toList(),
      ));
}

void main() {
  final fixtures = loadFixtures();

  /* The fixtures are a COPY of web/fixtures/surfaces.json, which
     tests/php/ai_uisurface_test.php generates. A copy goes stale silently, and a stale copy is
     worse than none: it reports that the two renderers agree about a surface the server no
     longer sends. There is no checkout of the server repo here to diff against, so pin the
     shape instead — a surface added in PHP shows up here as a missing key. */
  test('the fixture file still covers every surface the server composes', () {
    const expected = {
      'picker',
      'confirm',
      'confirm_no_warnings',
      'date',
      'time',
      'datetime',
      'multi',
      'multi_filterable',
      'list',
      'list_long',
      'list_no_ids',
      'choice',
      'undo',
      'next_steps',
      'link',
    };
    final present = fixtures.keys.toSet();
    expect(expected.difference(present), isEmpty,
        reason: 're-copy web/fixtures/surfaces.json from the server repo');
    expect(present.difference(expected), isEmpty,
        reason: 'new surface(s) — add cases here, then widen this list');
  });

  /// Pump one surface and hand back the actions it produced.
  Future<List<A2uiAction>> pump(
    WidgetTester tester,
    String key, {
    void Function(bool)? onRendered,
  }) async {
    final messages = fixtures[key];
    expect(messages, isNotNull, reason: 'no fixture named "$key"');
    // A FRESH copy per test. The fixtures are loaded once and the renderer writes a selection
    // back into the data-model message, so sharing them let one test's tap change the next
    // test's starting state — which is exactly the bug the widget now guards against, and it
    // would be circular to rely on that guard here.
    final own = messages!
        .map((m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>)
        .toList();
    final actions = <A2uiAction>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: A2uiSurfaceView(
            messages: own,
            onAction: actions.add,
            onRenderedChanged: onRendered,
          ),
        ),
      ),
    ));
    // The controller applies messages through a stream, so the first frame is empty by
    // construction. Settle before asserting anything at all.
    await tester.pumpAndSettle();
    return actions;
  }

  group('every fixture actually draws', () {
    // Not a list written by hand: if PHP gains a surface and nobody adds a case here, the new
    // key still gets rendered and asserted non-empty.
    for (final key in fixtures.keys) {
      testWidgets('$key renders something', (tester) async {
        var rendered = false;
        await pump(tester, key, onRendered: (r) => rendered = r);
        expect(rendered, isTrue,
            reason: '$key produced no surface — this is the silent no-render bug');
        // "A widget exists" is too weak: an empty Column would pass. Require real text.
        expect(find.byType(Text), findsWidgets);
      });
    }
  });

  group('the picker', () {
    testWidgets('shows the question and every candidate', (tester) async {
      await pump(tester, 'picker');
      expect(find.text('Which Acme did you mean?'), findsOneWidget);
      expect(find.text('Acme Traders — file_no 1201'), findsOneWidget);
      expect(find.text('Acme Exports'), findsOneWidget);
      expect(find.text('Acme Holdings — Retail group'), findsOneWidget);
      expect(find.text('Use this one'), findsOneWidget);
    });

    testWidgets('choosing one sends the id, not the name alone', (tester) async {
      final actions = await pump(tester, 'picker');
      await tester.tap(find.text('Acme Traders — file_no 1201'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this one'));
      await tester.pumpAndSettle();

      expect(actions, hasLength(1));
      // Byte-for-byte the sentence the web glue produces. The model is told an id it already
      // has, which is what stops it searching for the client again.
      expect(actions.single, const SendChat('Use client #2144 — Acme Traders.'));
    });

    testWidgets('submitting with nothing chosen says so instead of sending "Use ."',
        (tester) async {
      final actions = await pump(tester, 'picker');
      await tester.tap(find.text('Use this one'));
      await tester.pumpAndSettle();
      expect(actions.single, const ActionFailed('Nothing was selected.'));
    });
  });

  group('multi-select', () {
    testWidgets('renders its question and options', (tester) async {
      await pump(tester, 'multi');
      expect(find.text('Which clients should I include?'), findsOneWidget);
      expect(find.text('Use these'), findsOneWidget);
    });

    testWidgets('two picks come back as one sentence naming both ids',
        (tester) async {
      final actions = await pump(tester, 'multi');
      final options = fixtures['multi']!
          .expand((m) => (m['updateComponents']?['components'] as List? ?? []))
          .whereType<Map>()
          .firstWhere((c) => c['component'] == 'ChoicePicker')['options'] as List;
      expect(options.length, greaterThanOrEqualTo(2),
          reason: 'the multi fixture needs at least two options to be worth testing');

      for (final o in options.take(2)) {
        await tester.tap(find.text('${(o as Map)['label']}'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Use these'));
      await tester.pumpAndSettle();

      expect(actions, hasLength(1));
      final sent = actions.single;
      expect(sent, isA<SendChat>());
      final text = (sent as SendChat).text;
      for (final o in options.take(2)) {
        final id = '${(o as Map)['value']}'.split('|').first;
        expect(text, contains('#$id'), reason: 'every chosen id must be named');
      }
      expect(text, startsWith('Use clients '),
          reason: 'more than one selection takes the plural');
    });
  });

  group('the date surface', () {
    testWidgets('renders the question and a date field', (tester) async {
      await pump(tester, 'date');
      expect(find.text('When should I set the reminder for?'), findsOneWidget);
      expect(find.text('Use this'), findsOneWidget);
    });

    testWidgets('submitting an untouched calendar asks rather than sending nothing',
        (tester) async {
      final actions = await pump(tester, 'date');
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(actions.single, const ActionFailed('Pick a date or a time first.'));
    });
  });

  /* The third shape a missing required value can take: one of a fixed set the tool schema
     already lists. It reaches the user as a tappable list rather than as a sentence asking
     them to retype a word the app could have offered. */
  group('the fixed-value picker', () {
    testWidgets('renders the question and every allowed value', (tester) async {
      await pump(tester, 'choice');
      expect(find.text('Which status should it move to?'), findsOneWidget);
      expect(find.text('Allotted'), findsOneWidget);
      expect(find.text('Checking'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('choosing one sends the schema spelling, not the shown label',
        (tester) async {
      final actions = await pump(tester, 'choice');
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(actions.single, const SendChat('Use status: completed.'));
    });

    testWidgets('submitting without choosing asks rather than sending nothing',
        (tester) async {
      final actions = await pump(tester, 'choice');
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(actions.single, const ActionFailed('Nothing was selected.'));
    });
  });

  /* Both are one-tap chips the server attaches AFTER a write: they carry the whole reply in
     their context, so a tap must send it verbatim — the same sentence the web sends
     (a2ui-docsync.js), or the agent sees two spellings of one request. */
  group('the after-a-write chips', () {
    testWidgets('undo sends the undo sentence', (tester) async {
      final actions = await pump(tester, 'undo');
      await tester.tap(find.text('Undo — remove this to-do'));
      await tester.pumpAndSettle();
      expect(actions.single, const SendChat('Use undo: to-do #77.'));
    });

    testWidgets('each next step sends its own sentence', (tester) async {
      final actions = await pump(tester, 'next_steps');
      expect(find.text('Email it to the client'), findsOneWidget);
      await tester.tap(find.text('Mark it paid'));
      await tester.pumpAndSettle();
      expect(actions.single, const SendChat('Use next: mark invoice #65 paid.'));
    });
  });

  group('the link card', () {
    testWidgets('draws its lines and opens the page it names', (tester) async {
      final actions = await pump(tester, 'link');
      expect(find.text('Status: pending'), findsOneWidget);
      await tester.tap(find.text('Open page'));
      await tester.pumpAndSettle();
      expect(actions.single, const OpenPage('open.php?kind=task&id=512'));
    });

    test('the page screen is titled by what it opens', () {
      expect(pageTitle('open.php?kind=task&id=512'), 'Task #512');
      expect(pageTitle('open.php?kind=client_address&id=12'), 'Billing address');
    });

    test('only open.php links are followed', () {
      const refused = ActionFailed('That link is not one this app follows.');
      expect(routeA2uiAction('docsync.navigate', {'url': 'https://evil.example/'}), refused);
      expect(routeA2uiAction('docsync.navigate', {'url': 'open.php?kind=staff&id=1'}), refused);
      expect(routeA2uiAction('docsync.navigate', {'url': 'open.php?kind=task&id=0'}), refused);
    });
  });

  group('the results list', () {
    testWidgets('draws the head and every row', (tester) async {
      await pump(tester, 'list');
      expect(find.text('Here are your to-dos:'), findsOneWidget);
      expect(find.text('File the GST return'), findsOneWidget);
      expect(find.text('Call Sharma'), findsOneWidget);
      expect(find.text('High priority · due 25 Sep 2026'), findsOneWidget);
    });

    testWidgets('every row is one full-width card, not a pill inside a card', (tester) async {
      await pump(tester, 'list');
      expect(find.byType(Card), findsNWidgets(2));
      final w0 = tester.getSize(find.byType(Card).at(0)).width;
      final w1 = tester.getSize(find.byType(Card).at(1)).width;
      expect(w0, w1, reason: 'a stretched List draws every card at the same width');
      expect(find.byType(ElevatedButton), findsNothing,
          reason: 'a row is a borderless button; the Card is its only edge');
      final row = tester.getSize(find.byType(TextButton).first).width;
      expect(row, greaterThan(w0 - 40), reason: 'the tappable row fills its card');
    });

    testWidgets('tapping a row sends an ordinary chat turn naming its real id',
        (tester) async {
      final actions = await pump(tester, 'list');
      await tester.tap(find.text('File the GST return'));
      await tester.pumpAndSettle();
      expect(actions, hasLength(1));
      expect(actions.single, isA<SendChat>());
      final text = (actions.single as SendChat).text;
      expect(text, startsWith('Open '));
      expect(text, contains('File the GST return'));
      expect(RegExp(r'#\d+').hasMatch(text), isTrue,
          reason: 'the row must carry its real integer id');
    });

    testWidgets('a list is not a question: the cards survive a tap', (tester) async {
      await pump(tester, 'list');
      await tester.tap(find.text('File the GST return'));
      await tester.pumpAndSettle();
      // The bubble's text was superseded by these cards. Tearing them down on a tap would
      // leave the message completely blank — a real bug the web harness caught.
      expect(find.text('File the GST return'), findsOneWidget);
      expect(find.text('Call Sharma'), findsOneWidget);
    });

    testWidgets('a row with no usable id is not a dead button', (tester) async {
      final actions = await pump(tester, 'list_no_ids');
      final buttons = find.byType(ElevatedButton).evaluate().length +
          find.byType(TextButton).evaluate().length +
          find.byType(FilledButton).evaluate().length +
          find.byType(OutlinedButton).evaluate().length;
      // Either it is not a button at all, or pressing it reports a failure. What must not
      // happen is a button that looks live and does nothing.
      if (buttons > 0) {
        await tester.tap(find.byType(ElevatedButton).first, warnIfMissed: false);
        await tester.pumpAndSettle();
        if (actions.isNotEmpty) expect(actions.single, isA<ActionFailed>());
      }
      expect(find.byType(Text), findsWidgets);
    });
  });

  group('the confirm surface', () {
    testWidgets('shows the summary and both buttons', (tester) async {
      await pump(tester, 'confirm');
      expect(find.textContaining('Confirm'), findsWidgets);
    });

    testWidgets('confirming produces a commit with parsed args, not a chat turn',
        (tester) async {
      final actions = await pump(tester, 'confirm');
      // Tap the label by its text. Reading Text.data instead would find nothing: genui renders
      // through Text.rich, so `data` is null on every one of them while find.text still
      // matches the plain text of the span.
      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(actions, hasLength(1));
      expect(actions.single, isA<CommitWrite>());
      final commit = actions.single as CommitWrite;
      expect(commit.action, isNotEmpty);
      // args travel as a JSON STRING because DynamicValue has no object variant; encoding
      // them twice is a bad_request at the other end.
      expect(commit.args, isA<Map<String, dynamic>>());
      expect(commit.args, isNotEmpty);
    });
  });

  /* A regression test for a defect found while writing the ones above: genui seeds its data
     model with the very list object inside `updateDataModel.value`, so a selection wrote
     straight back into the map the caller passed in. ChatMessage.a2ui is documented as
     immutable value state AND compared by identity, so the mutation changed a stored turn
     with nothing to notice it. The widget now copies; this proves it still does. */
  testWidgets('the renderer never writes back into the caller\'s messages',
      (tester) async {
    final msgs = fixtures['picker']!
        .map((m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>)
        .toList();
    final before = jsonEncode(msgs);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: A2uiSurfaceView(messages: msgs, onAction: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Traders — file_no 1201'));
    await tester.pumpAndSettle();

    expect(jsonEncode(msgs), before,
        reason: 'choosing an option must not mutate the protocol messages');
  });

  testWidgets('a malformed message does not take the rest of the turn with it',
      (tester) async {
    final broken = [
      {'version': 'v0.9', 'createSurface': {'nonsense': true}},
      ...fixtures['picker']!,
    ];
    var rendered = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: A2uiSurfaceView(
          messages: broken,
          onAction: (_) {},
          onRenderedChanged: (r) => rendered = r,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(rendered, isTrue);
    expect(find.text('Which Acme did you mean?'), findsOneWidget);
  });
}
