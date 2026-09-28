// Trail pairing, driven through the REAL ChatController with a scripted stream.
//
// The four things that have to hold, and each of which is a bug someone shipped:
//   - a start with no finish does not spin forever
//   - a finish with no start does not appear from nowhere (legacy events do, ticked)
//   - transient steps vanish from the finished list
//   - a confirm-terminal turn, which never sends `final`, still collapses

import 'package:docsync_app/features/chat/controller/chat_controller.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scripted_chat_repository.dart';

Future<ChatState> run(List<Map<String, dynamic>> script) async {
  final container = ProviderContainer(overrides: [
    chatRepositoryProvider.overrideWithValue(ScriptedChatRepository(script)),
  ]);
  addTearDown(container.dispose);
  await container.read(chatControllerProvider.notifier).send('hello');
  return container.read(chatControllerProvider);
}

List<String> labels(ChatState s) => s.trail.map((e) => e.label).toList();

void main() {
  test('the opening line closes as soon as the first step starts', () async {
    final s = await run([
      {'type': 'step_start', 'seq': 1, 'kind': 'tool', 'label': 'Adding a to-do'},
      {'type': 'step', 'seq': 1, 'done_label': 'Added the to-do'},
      {'type': 'final', 'answer': 'Done.', 'elapsed': 2.0},
    ]);
    expect(labels(s), ['Sent your question', 'Added the to-do']);
    expect(s.trail.every((e) => e.done), isTrue);
    expect(s.trailDone, isTrue);
    expect(s.elapsed, 2.0);
  });

  test('a start with no finish does not spin forever', () async {
    final s = await run([
      {'type': 'step_start', 'seq': 1, 'kind': 'search', 'label': 'Searching'},
      {'type': 'final', 'answer': 'x'},
    ]);
    expect(s.trail.last.label, 'Searching'); // keeps the running label
    expect(s.trail.every((e) => e.done), isTrue);
  });

  test('a stream that just ends still closes and collapses the trail', () async {
    // No final, no confirm, no error — the stream simply stops.
    final s = await run([
      {'type': 'step_start', 'seq': 1, 'kind': 'tool', 'label': 'Working'},
    ]);
    expect(s.trailDone, isTrue);
    expect(s.trail.every((e) => e.done), isTrue);
    expect(s.sending, isFalse);
  });

  test('a finish with no start appears only if it is a known legacy tool',
      () async {
    final s = await run([
      {'type': 'step', 'tool': 'fetch_more'},
      {'type': 'step', 'tool': 'a_tool_from_the_future'},
      {'type': 'final', 'answer': 'x'},
    ]);
    // The unknown one drew nothing at all; no blank row.
    expect(labels(s), ['Sending your question', 'Read more of a document']);
  });

  test('a step for a seq that was never opened does not close another line',
      () async {
    final s = await run([
      {'type': 'step_start', 'seq': 1, 'kind': 'tool', 'label': 'One'},
      {'type': 'step', 'seq': 9, 'done_label': 'Nine finished'},
      {'type': 'final', 'answer': 'x'},
    ]);
    expect(labels(s), ['Sent your question', 'One', 'Nine finished']);
    // "One" was closed by the end of the turn, not by seq 9.
    expect(s.trail[1].label, 'One');
  });

  test('transient steps show while running and vanish from the history',
      () async {
    final container = ProviderContainer(overrides: [
      chatRepositoryProvider.overrideWithValue(ScriptedChatRepository([
        {
          'type': 'step_start',
          'seq': 1,
          'kind': 'decide',
          'label': 'Planning the next step',
          'transient': true
        },
        {'type': 'step', 'seq': 1, 'done_label': 'Planned the next step'},
        {
          'type': 'step_start',
          'seq': 2,
          'kind': 'decide',
          'label': 'Planning the next step',
          'transient': true
        },
        {'type': 'step', 'seq': 2, 'done_label': 'Planned the next step'},
        {'type': 'step_start', 'seq': 3, 'kind': 'tool', 'label': 'Adding'},
        {'type': 'step', 'seq': 3, 'done_label': 'Added the to-do'},
        {'type': 'final', 'answer': 'Done.'},
      ])),
    ]);
    addTearDown(container.dispose);

    final seen = <List<String>>[];
    container.listen(chatControllerProvider, (_, s) {
      seen.add(s.trail.map((e) => e.label).toList());
    }, fireImmediately: false);

    await container.read(chatControllerProvider.notifier).send('hi');
    final s = container.read(chatControllerProvider);

    // It WAS shown live at some point...
    expect(seen.any((l) => l.contains('Planning the next step')), isTrue);
    // ...and only the second transient round survived long enough to be closed,
    // but neither is in the finished trail.
    expect(labels(s), ['Sent your question', 'Added the to-do']);
    expect(s.trail.any((e) => e.transient), isFalse);
  });

  test('a failed step is marked failed, not ticked', () async {
    final s = await run([
      {'type': 'step_start', 'seq': 1, 'kind': 'tool', 'label': 'Adding'},
      {
        'type': 'step',
        'seq': 1,
        'done_label': 'Could not add the to-do',
        'result': {'ok': false}
      },
      {'type': 'final', 'answer': 'x'},
    ]);
    expect(s.trail.last.failed, isTrue);
    expect(s.trail.last.label, 'Could not add the to-do');
  });

  test('a confirm-terminal turn collapses the trail and prints no "(no answer)"',
      () async {
    final s = await run([
      {'type': 'step_start', 'seq': 1, 'kind': 'tool', 'label': 'Preparing'},
      {'type': 'step', 'seq': 1, 'done_label': 'Prepared the change'},
      {
        'type': 'confirm',
        'name': 'set_task_status',
        'summary': 'Move task #581 to completed.',
        'commit_args': {'task_creation_id': 581, 'status': 'completed'},
        'warnings': <String>[],
      },
      {'type': 'usage', 'prompt_tokens': 10},
    ]);

    expect(s.trailDone, isTrue);
    expect(labels(s), ['Sent your question', 'Prepared the change']);

    final msg = s.messages.last;
    expect(msg.streaming, isFalse);
    expect(msg.confirm, isNotNull);
    expect(msg.confirm!.name, 'set_task_status');
    expect(msg.confirm!.commitArgs['task_creation_id'], 581);
    // The old code wrote "(no answer)" here, under the confirmation card.
    expect(msg.content, isEmpty);
  });

  test('a turn with neither text nor a widget still says something', () async {
    final s = await run([
      {'type': 'final', 'answer': ''},
    ]);
    expect(s.messages.last.content, 'No answer.');
  });

  test('a2ui messages are collected on the turn in arrival order', () async {
    final s = await run([
      {
        'type': 'a2ui',
        'msg': {
          'version': 'v0.9',
          'createSurface': {'surfaceId': 's1', 'catalogId': 'c'}
        }
      },
      {
        'type': 'a2ui',
        'msg': {
          'version': 'v0.9',
          'updateComponents': {'surfaceId': 's1', 'components': <dynamic>[]}
        }
      },
      {'type': 'final', 'answer': 'pick one'},
    ]);
    final a2ui = s.messages.last.a2ui;
    expect(a2ui, hasLength(2));
    expect(a2ui.first.containsKey('createSurface'), isTrue);
    expect(a2ui.last.containsKey('updateComponents'), isTrue);
  });
}
