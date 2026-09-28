// Following a turn that is already running, driven through the REAL ChatController.
//
// WHY THIS MATTERS. A turn belongs to the conversation on the server, not to the client that
// started it: it keeps running after the app is killed, and it may have been started on the web.
// Opening such a chat has to pick the turn up rather than show a question with nothing under it —
// which is exactly the bug this whole feature exists to fix, reported from a live chat and then
// confirmed in the database (a user message with no assistant message at all).
//
// The property worth testing is not "following works" but that **both paths fold identically**.
// A resumed turn replays the same events a live one sent, so if the two diverge, a followed turn
// renders differently from the one that produced it — and nobody would notice until two devices
// were showing the same chat and disagreeing about it.

import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_chat_repository.dart';

/// The events a real turn sends: a couple of steps, some text, and a final.
const script = <Map<String, dynamic>>[
  {'type': 'conversation', 'id': 42, 'turn': 7},
  {'type': 'step_start', 'seq': 1, 'kind': 'tool', 'label': 'Looking up the client'},
  {'type': 'step', 'seq': 1, 'done_label': 'Found the client'},
  {'type': 'token', 'text': 'Acme Traders '},
  {'type': 'token', 'text': 'has 3 open tasks.'},
  {'type': 'final', 'answer': 'Acme Traders has 3 open tasks.', 'elapsed': 4.0},
];

({ProviderContainer container, ScriptedChatRepository repo}) harness({
  bool live = true,
  List<ChatMessage> messages = const [],
}) {
  final repo = ScriptedChatRepository(script, messages: messages)..hasLiveTurn = live;
  final container = ProviderContainer(
    overrides: [chatRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

/* openConversation deliberately does NOT await the follow: opening a chat must never be held
   up waiting on a turn that might run for a minute. That makes it unobservable until the
   microtasks it queued have run, which is what this is for. */
Future<void> settle() => Future<void>.delayed(Duration.zero);

List<String> labels(ChatState s) => s.trail.map((e) => e.label).toList();

void main() {
  test('following renders the same answer the live turn would have', () async {
    final h = harness();
    await h.container.read(chatControllerProvider.notifier).follow(42);
    final s = h.container.read(chatControllerProvider);

    expect(h.repo.followed, [42]);
    expect(s.messages.last.content, 'Acme Traders has 3 open tasks.');
    expect(s.messages.last.streaming, isFalse);
    expect(s.status, ChatStatus.idle);
  });

  /* The one that guards against the two paths drifting. Same script, two entry points, and the
     only legitimate difference is the user message a live turn appends for itself. */
  test('a followed turn and a live turn agree on everything but the question', () async {
    final live = harness();
    await live.container.read(chatControllerProvider.notifier).send('how many tasks?');
    final a = live.container.read(chatControllerProvider);

    final followed = harness();
    await followed.container.read(chatControllerProvider.notifier).follow(42);
    final b = followed.container.read(chatControllerProvider);

    expect(b.messages.last.content, a.messages.last.content);
    expect(b.trailDone, a.trailDone);
    expect(b.elapsed, a.elapsed);
    // The trail differs only in its opening line, which honestly says what happened.
    expect(labels(a), ['Sent your question', 'Found the client']);
    expect(labels(b), ['Picked up this answer', 'Found the client']);
  });

  /* A live turn appends the question it just asked. A followed one must NOT: the question is
     already in the transcript that was loaded a moment earlier, and appending it again would
     show the user their own message twice. */
  test('following does not duplicate the question already in the transcript', () async {
    final existing = [
      const ChatMessage(role: 'user', content: 'how many tasks?'),
    ];
    final h = harness(messages: existing);
    final ctl = h.container.read(chatControllerProvider.notifier);
    // Through openConversation, because that is the only way this happens for real: the
    // transcript is loaded first, and the turn is joined against what it already contains.
    await ctl.openConversation(42);
    await settle();
    final s = h.container.read(chatControllerProvider);

    expect(s.messages.where((m) => m.role == 'user').length, 1);
    expect(s.messages.length, 2); // the question, and the answer that arrived
  });

  /* The common case by far: the chat is opened and nothing is running. It must cost nothing
     visible — no placeholder bubble left behind, no spinner that never resolves. */
  test('nothing running leaves the transcript exactly as it was', () async {
    final existing = [
      const ChatMessage(role: 'user', content: 'how many tasks?'),
      const ChatMessage(role: 'assistant', content: 'Three.'),
    ];
    final h = harness(live: false, messages: existing);
    final ctl = h.container.read(chatControllerProvider.notifier);
    // Seed the state the way openConversation would.
    await ctl.openConversation(42);
    await settle();
    final s = h.container.read(chatControllerProvider);

    expect(s.messages.length, 2);
    expect(s.messages.last.content, 'Three.');
    expect(s.messages.last.streaming, isFalse);
    expect(s.status, ChatStatus.idle);
  });

  test('opening a conversation always asks whether a turn is still running', () async {
    final h = harness(live: false);
    await h.container.read(chatControllerProvider.notifier).openConversation(42);
    await settle();
    expect(h.repo.followed, [42]);
  });

  /* follow() is called on every open, including while the user is mid-question on that same
     chat. Two folds writing to `messages.last` at once would interleave an answer with itself. */
  test('following is refused while a turn of our own is in flight', () async {
    final h = harness();
    final ctl = h.container.read(chatControllerProvider.notifier);
    final sending = ctl.send('how many tasks?');
    await ctl.follow(42); // must be a no-op, not a second fold
    await sending;

    expect(h.repo.followed, isEmpty);
    expect(h.container.read(chatControllerProvider).messages.length, 2);
  });

  test('a conversation that has never been saved has nothing to follow', () async {
    final h = harness();
    await h.container.read(chatControllerProvider.notifier).follow(0);
    expect(h.repo.followed, isEmpty);
  });
}
