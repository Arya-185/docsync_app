// Stop, and the two ways a tap during a running turn used to go wrong — driven through the
// REAL ChatController with a repository whose stream can be held open mid-turn.
//
// Stop is not a local cancel: the turn lives on the server and keeps running if the app
// merely hangs up. It is a request to rag_stop.php, after which the SAME stream carries on
// until the agent reaches its next check and ends with `final.stopped`.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:docsync_app/shared/widgets/file_card.dart';
import 'package:docsync_app/features/settings/controller/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_chat_repository.dart';

/// Sends [head], then waits for [release] before sending [tail] — a turn that is visibly
/// "still running" for as long as the test wants.
class GatedRepository extends ScriptedChatRepository {
  GatedRepository(this.head, this.tail) : super(const []);
  final List<Map<String, dynamic>> head;
  final List<Map<String, dynamic>> tail;
  final release = Completer<void>();

  @override
  Stream<RagEvent> answerStream(
    String query, {
    int conv = 0,
    int k = 10,
    bool voice = false,
    String? lang,
    CancelToken? cancel,
  }) async* {
    asked.add(query);
    voiceFlags.add((voice: voice, lang: lang));
    for (final j in head) {
      yield RagEvent.fromJson(j);
    }
    await release.future;
    for (final j in tail) {
      yield RagEvent.fromJson(j);
    }
  }
}

({ProviderContainer container, GatedRepository repo}) harness(
  List<Map<String, dynamic>> head,
  List<Map<String, dynamic>> tail,
) {
  final repo = GatedRepository(head, tail);
  final container = ProviderContainer(
    overrides: [chatRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('Stop asks the server, shows Stopping, and a bare stopped final reads "Stopped."',
      () async {
    final h = harness(
      [
        {'type': 'conversation', 'id': 42, 'turn': 1},
        {'type': 'step_start', 'seq': 1, 'label': 'Looking up the client'},
      ],
      [
        {'type': 'final', 'answer': '', 'stopped': true},
      ],
    );
    final ctrl = h.container.read(chatControllerProvider.notifier);
    final turn = ctrl.send('who owes us money');
    await settle();

    expect(h.container.read(chatControllerProvider).sending, isTrue);
    await ctrl.stop();
    expect(h.repo.stopped, [42]);
    expect(h.container.read(chatControllerProvider).stopping, isTrue);

    h.repo.release.complete();
    await turn;
    final s = h.container.read(chatControllerProvider);
    expect(s.messages.last.content, 'Stopped.');
    expect(s.sending, isFalse);
    expect(s.stopping, isFalse);
  });

  test('Stop before the server has named the conversation is sent once it does', () async {
    final h = harness(
      const [],
      [
        {'type': 'conversation', 'id': 7, 'turn': 1},
        {'type': 'final', 'answer': 'Partial answer.', 'stopped': true},
      ],
    );
    final ctrl = h.container.read(chatControllerProvider.notifier);
    final turn = ctrl.send('a brand-new chat');
    await settle();

    await ctrl.stop();
    expect(h.repo.stopped, isEmpty, reason: 'no conversation id to stop yet');

    h.repo.release.complete();
    await turn;
    expect(h.repo.stopped, [7]);
    // Text the agent produced before stopping is kept, not replaced by "Stopped.".
    expect(h.container.read(chatControllerProvider).messages.last.content, 'Partial answer.');
  });

  test('a second question while one is running is refused, not silently dropped', () async {
    final h = harness(
      [
        {'type': 'conversation', 'id': 3, 'turn': 1},
      ],
      [
        {'type': 'final', 'answer': 'Done.'},
      ],
    );
    final ctrl = h.container.read(chatControllerProvider.notifier);
    final first = ctrl.send('first');
    await settle();

    expect(await ctrl.send('second'), isFalse);
    expect(h.repo.asked, ['first']);

    h.repo.release.complete();
    expect(await first, isTrue);
  });

  test('a voice turn carries voice and lang to the request', () async {
    final h = harness(const [], [
      {'type': 'final', 'answer': 'Ok.'},
    ]);
    h.repo.release.complete();
    await h.container
        .read(chatControllerProvider.notifier)
        .send('kal ka reminder', voice: true, lang: 'hi-IN');
    expect(h.repo.voiceFlags.single, (voice: true, lang: 'hi-IN'));
  });

  group('step timing', () {
    test('closing a timed line stamps how long it ran, once', () {
      final open = ChatStep(
        seq: 1,
        label: 'Looking up',
        startedAt: DateTime.now().subtract(const Duration(milliseconds: 1500)),
      );
      final closed = open.copyWith(done: true);
      expect(closed.seconds, isNotNull);
      expect(closed.seconds!, greaterThanOrEqualTo(1.5));
      // Relabelling a closed line must not re-time it.
      expect(closed.copyWith(label: 'Found it').seconds, closed.seconds);
    });

    test('timing is display-only: it does not change equality', () {
      final a = ChatStep(seq: 1, label: 'x', done: true, startedAt: DateTime(2020));
      const b = ChatStep(seq: 1, label: 'x', done: true);
      expect(a, b);
    });

    test('an untimed line (legacy or loaded) has no seconds', () {
      expect(const ChatStep(seq: 2, label: 'y').copyWith(done: true).seconds, isNull);
    });
  });

  test('file kinds come from the extension, case-insensitively', () {
    expect(FileKind.of('GSTR-3B.PDF').label, 'PDF');
    expect(FileKind.of('ledger.xlsx').label, 'XLS');
    expect(FileKind.of('notes.docx').label, 'DOC');
    expect(FileKind.of('scan.jpeg').label, 'IMG');
    expect(FileKind.of('README').label, 'FILE');
    expect(FileKind.of('data.parquet').label, 'PARQUET');
  });

  test('voice language codes are what the server whitelists', () {
    expect(VoiceLang.auto.code, isNull);
    expect(VoiceLang.english.code, 'en-IN');
    expect(VoiceLang.hindi.code, 'hi-IN');
  });
}
