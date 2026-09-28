// The ai_commit.php contract, and the card that drives it.
//
// Two things are asserted that a reviewer cannot see by reading the widget:
//   - the POST body carries `action`, `args` (a JSON STRING) and `conv`, and NO
//     `Origin` header — the server's same-origin guard is permissive only when
//     both Origin and Referer are absent, so adding one turns 200 into 403;
//   - a FAILED commit leaves the Confirm button on screen, so the user can retry.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:docsync_app/core/network/api_client.dart';
import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:docsync_app/features/chat/model/chat_repository.dart';
import 'package:docsync_app/features/chat/view/widgets/confirm_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the request instead of sending it.
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.body);

  /// The JSON ai_commit.php would have replied with.
  final Map<String, dynamic> body;
  RequestOptions? seen;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// An [ApiClient] whose dio we control. `ApiClient.create()` needs
/// path_provider, which is not available in a plain test.
class _TestApiClient implements ApiClient {
  _TestApiClient(this.dio);

  @override
  final Dio dio;

  @override
  String get baseUrl => 'https://example.test';

  @override
  String url(String path) => '$baseUrl$path';

  @override
  Future<void> clearCookies() async {}
  @override
  Future<String?> cookieValue(String name) async => null;
  @override
  Future<String> cookieHeader() async => '';
  @override
  void setBaseUrl(String url) {}
}

({ChatRepository repo, _CapturingAdapter adapter}) makeRepo(
    Map<String, dynamic> reply) {
  final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
  final adapter = _CapturingAdapter(reply);
  dio.httpClientAdapter = adapter;
  return (repo: ChatRepository(_TestApiClient(dio)), adapter: adapter);
}

void main() {
  test('the POST carries action, args and conv — and no Origin', () async {
    final (:repo, :adapter) = makeRepo({'ok': true, 'message': 'Task updated.'});

    final res = await repo.commit(
      'set_task_status',
      {'task_creation_id': 581, 'status': 'completed'},
      conv: 42,
    );

    expect(res.ok, isTrue);
    expect(res.message, 'Task updated.');

    final sent = adapter.seen!;
    expect(sent.method, 'POST');
    expect(sent.path, endsWith('/app/ai_commit.php'));
    expect(sent.contentType, startsWith(Headers.formUrlEncodedContentType));

    final data = sent.data as Map;
    expect(data['action'], 'set_task_status');
    expect(data['conv'], 42);
    // args is a JSON STRING on the wire, encoded exactly once.
    expect(data['args'], isA<String>());
    expect(jsonDecode(data['args'] as String),
        {'task_creation_id': 581, 'status': 'completed'});

    final headerNames =
        sent.headers.keys.map((k) => k.toLowerCase()).toList();
    expect(headerNames, isNot(contains('origin')));
    expect(headerNames, isNot(contains('referer')));
    expect(sent.headers['X-DocSync-App'], '1');
  });

  test('ok:false is surfaced as a failure with the server message', () async {
    final (:repo, adapter: _) = makeRepo(
        {'ok': false, 'error': 'forbidden', 'message': 'No access.'});
    final res = await repo.commit('add_todo', const {'title': 'x'});
    expect(res.ok, isFalse);
    expect(res.message, 'No access.');
  });

  Widget host(ChatRepository repo, ConfirmProposal p) => ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: Scaffold(body: ConfirmCard(proposal: p))),
      );

  const proposal = ConfirmProposal(
    name: 'set_task_status',
    summary: 'Move task #581 to completed.',
    warnings: ['This notifies the person who allotted it.'],
    commitArgs: {'task_creation_id': 581},
  );

  testWidgets('a successful commit retires the buttons', (tester) async {
    final (:repo, adapter: _) = makeRepo({'ok': true, 'message': 'Done.'});
    await tester.pumpWidget(host(repo, proposal));

    expect(find.text('Please confirm'), findsOneWidget);
    expect(find.text('Move task #581 to completed.'), findsOneWidget);
    expect(find.text('This notifies the person who allotted it.'),
        findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Done.'), findsOneWidget);
    // The write happened; the button must not be able to fire twice.
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('a failed commit leaves the card usable for a retry',
      (tester) async {
    final (:repo, :adapter) =
        makeRepo({'ok': false, 'message': 'Could not complete the action.'});
    await tester.pumpWidget(host(repo, proposal));

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Could not complete the action.'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget); // still there
    expect(find.text('Cancel'), findsOneWidget);

    // And it really can be pressed again.
    adapter.body
      ..['ok'] = true
      ..['message'] = 'Done.';
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Done.'), findsOneWidget);
  });

  testWidgets('Cancel writes nothing', (tester) async {
    final (:repo, :adapter) = makeRepo({'ok': true});
    await tester.pumpWidget(host(repo, proposal));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled.'), findsOneWidget);
    expect(adapter.seen, isNull);
  });
}
