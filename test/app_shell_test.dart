// The signed-in shell: header, the three tabs, and switching between them.
//
// Note: pump(duration), never pumpAndSettle — the voice orb breathes on a repeating clock,
// so the tree never settles by design.

import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/home/view/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_chat_repository.dart';

Future<void> pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      chatRepositoryProvider.overrideWithValue(ScriptedChatRepository(const [])),
    ],
    child: const MaterialApp(home: AppShell()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('opens on Voice with the header, the orb and suggestions', (tester) async {
    await pumpShell(tester);
    expect(find.text('DocSync'), findsOneWidget);
    expect(find.text('What can I do\nfor you today?'), findsOneWidget);
    expect(find.text('You can also say'), findsOneWidget);
    expect(find.byTooltip('Search documents'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('the pill switches to Chat and Recent', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Chat'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ask about your clients'), findsOneWidget);

    await tester.tap(find.text('Recent'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('No conversations yet'), findsOneWidget);
  });
}
