// The two things a bubble has to get right about TEXT.
//
//  1. Markdown. The model writes `**bold**` and bullet lists; the bubble used to print them
//     raw, so answers arrived littered with asterisks.
//  2. Superseding. A results list is sent twice — as cards and as the same rows in prose —
//     and the prose may only be dropped once the cards are really on screen.
//
// The second is the dangerous one. Dropping the text on the strength of "the server said it
// sent a surface" is how a client ends up showing an empty bubble when rendering fails.

import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:docsync_app/features/chat/view/widgets/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> pumpBubble(WidgetTester tester, ChatMessage m) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ChatBubble(message: m)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Everything actually painted.
///
/// Both sources are needed. Selectable text — which is all of ours, deliberately — is drawn by
/// an [EditableText] and never appears as a [RichText], so reading only RichText reports an
/// empty screen for a bubble that is rendering perfectly well.
///
/// Reading the PAINTED text is the point: it is markdown-rendered, so a literal '**' showing up
/// here means the source was printed raw.
String shownText(WidgetTester tester) => [
      ...tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((e) => e.controller.text),
      ...tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText()),
    ].join('\n');

void main() {
  group('superseding is conditional, never assumed', () {
    const rows = '- #41 File the GST return\n- #42 Call Sharma';
    const answer = 'Here are your to-dos:\n$rows';

    test('nothing is dropped unless the surface rendered', () {
      const m = ChatMessage(
        role: 'assistant',
        content: answer,
        supersedes: [rows],
      );
      // The default is the safe one, and it is the default for a reason.
      expect(m.visibleContent(), answer);
      expect(m.visibleContent(rendered: false), answer);
    });

    test('once it has rendered, the duplicated block goes', () {
      const m = ChatMessage(
        role: 'assistant',
        content: answer,
        supersedes: [rows],
      );
      final visible = m.visibleContent(rendered: true);
      expect(visible, 'Here are your to-dos:');
      expect(visible, isNot(contains('File the GST return')));
    });

    test('a block that is not in the answer changes nothing', () {
      const m = ChatMessage(
        role: 'assistant',
        content: answer,
        supersedes: ['rows that were never written'],
      );
      expect(m.visibleContent(rendered: true), answer);
    });

    test('removing a middle block does not leave a ragged hole', () {
      const m = ChatMessage(
        role: 'assistant',
        content: 'Before.\n\n$rows\n\nAfter.',
        supersedes: [rows],
      );
      final visible = m.visibleContent(rendered: true);
      expect(visible, 'Before.\n\nAfter.');
      expect(RegExp(r'\n{3,}').hasMatch(visible), isFalse);
    });

    test('several surfaces each drop their own block', () {
      const a = '- #41 One';
      const b = '- #7 Two';
      const m = ChatMessage(
        role: 'assistant',
        content: 'Todos:\n$a\nReminders:\n$b',
        supersedes: [a, b],
      );
      final visible = m.visibleContent(rendered: true);
      expect(visible, isNot(contains('#41')));
      expect(visible, isNot(contains('#7')));
      expect(visible, contains('Todos:'));
      expect(visible, contains('Reminders:'));
    });

    testWidgets('a turn with no surface keeps every row on screen',
        (tester) async {
      // The whole answer must survive: no a2ui messages arrived, so nothing rendered.
      await pumpBubble(
        tester,
        const ChatMessage(
            role: 'assistant', content: answer, supersedes: [rows]),
      );
      expect(shownText(tester), contains('File the GST return'));
      expect(shownText(tester), contains('Call Sharma'));
    });
  });

  group('markdown', () {
    testWidgets('an assistant answer is rendered, not printed raw',
        (tester) async {
      await pumpBubble(
        tester,
        const ChatMessage(
          role: 'assistant',
          content: 'The total is **12,400** for *Acme*.',
        ),
      );
      final all = shownText(tester);
      expect(all, contains('12,400'));
      expect(all, isNot(contains('**')),
          reason: 'literal asterisks mean the Markdown was not rendered');
      expect(all, isNot(contains('*Acme*')));
    });

    testWidgets('a bullet list becomes a list', (tester) async {
      await pumpBubble(
        tester,
        const ChatMessage(
          role: 'assistant',
          content: 'Pending:\n- File the GST return\n- Call Sharma',
        ),
      );
      final all = shownText(tester);
      expect(all, contains('File the GST return'));
      expect(all, contains('Call Sharma'));
      // The bullet marker is drawn, not left as the source character at line start.
      expect(all, isNot(contains('- File the GST return')));
    });

    testWidgets('the answer stays selectable', (tester) async {
      await pumpBubble(
        tester,
        const ChatMessage(role: 'assistant', content: 'Copy **this** figure.'),
      );
      // Users copy figures out of answers; rendering Markdown must not cost them that.
      // Selectable text is drawn by an EditableText; MarkdownBody(selectable: true) uses one.
      expect(find.byType(SelectableText), findsWidgets);
    });

    testWidgets('what the USER typed is never reinterpreted', (tester) async {
      // A person writing about a discount is not writing Markdown. Parsing their words would
      // silently eat the asterisks and change what they said.
      await pumpBubble(
        tester,
        const ChatMessage(role: 'user', content: 'Apply the 10% *special* rate'),
      );
      expect(shownText(tester), contains('*special*'));
    });
  });
}
