// RagEvent.fromJson over realistic payloads for every event type the server emits.
//
// The load-bearing case is the LAST one: an unknown type must still map to
// `ignore`. That property is the whole reason the SSE contract can be extended
// additively — an older build has to keep working when a new event appears.

import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RagEvent.fromJson', () {
    test('conversation', () {
      final e = RagEvent.fromJson({'type': 'conversation', 'id': 412});
      expect(e.type, RagEventType.conversation);
      expect(e.conversationId, 412);
    });

    test('token and thinking', () {
      expect(RagEvent.fromJson({'type': 'token', 'text': 'Hel'}).text, 'Hel');
      expect(
        RagEvent.fromJson({'type': 'thinking', 'text': 'hmm'}).type,
        RagEventType.thinking,
      );
    });

    test('step_start carries seq, label, kind and transient', () {
      final e = RagEvent.fromJson({
        'type': 'step_start',
        'seq': 3,
        'kind': 'decide',
        'name': '',
        'label': 'Planning the next step',
        'transient': true,
      });
      expect(e.type, RagEventType.stepStart);
      expect(e.seq, 3);
      expect(e.kind, 'decide');
      expect(e.label, 'Planning the next step');
      expect(e.transient, isTrue);
    });

    test('step with seq carries done_label and is not failed', () {
      final e = RagEvent.fromJson({
        'type': 'step',
        'tool': 'tool',
        'name': 'add_todo',
        'seq': 4,
        'done_label': 'Added the to-do',
      });
      expect(e.seq, 4);
      expect(e.doneLabel, 'Added the to-do');
      expect(e.failed, isFalse);
    });

    test('a legacy step has a NULL seq, not zero', () {
      // Coerced to 0 they would all close each other's trail lines.
      final e = RagEvent.fromJson({
        'type': 'step',
        'tool': 'fetch_more',
      });
      expect(e.seq, isNull);
      expect(e.legacyLabel, 'Read more of a document');
    });

    test('step failure is detected from error, skipped or result.ok', () {
      expect(
        RagEvent.fromJson({'type': 'step', 'seq': 1, 'error': 'boom'}).failed,
        isTrue,
      );
      expect(
        RagEvent.fromJson(
            {'type': 'step', 'seq': 1, 'skipped': 'already performed'}).failed,
        isTrue,
      );
      expect(
        RagEvent.fromJson({
          'type': 'step',
          'seq': 1,
          'result': {'ok': false}
        }).failed,
        isTrue,
      );
      expect(
        RagEvent.fromJson({
          'type': 'step',
          'seq': 1,
          'result': {'ok': true}
        }).failed,
        isFalse,
      );
    });

    test('legacy labels match the web renderer, and unknown tools draw nothing',
        () {
      String? label(Map<String, dynamic> j) =>
          RagEvent.fromJson({'type': 'step', ...j}).legacyLabel;

      expect(label({'tool': 'queued', 'message': 'Queued for the main PC'}),
          'Queued for the main PC');
      expect(label({'tool': 'node', 'where': 'main'}), 'Reasoning on this PC');
      expect(label({'tool': 'node', 'where': 'worker', 'node': 'DESK-2'}),
          'Reasoning on DESK-2');
      expect(label({'tool': 'node', 'where': 'worker'}),
          'Reasoning on a worker PC');
      expect(label({'tool': 'search', 'query': 'gst'}), 'Searched: gst');
      expect(label({'tool': 'expand_file'}), 'Read a whole document');
      expect(label({'tool': 'read_original'}), 'Re-read the original file');
      expect(label({'tool': 'error', 'message': 'nope'}), 'nope');
      // No line at all — a blank row is worse than no row.
      expect(label({'tool': 'something_new'}), isNull);
    });

    test('a2ui passes the raw message through', () {
      final e = RagEvent.fromJson({
        'type': 'a2ui',
        'msg': {
          'version': 'v0.9',
          'createSurface': {'surfaceId': 'pick_client_1', 'catalogId': 'c'}
        }
      });
      expect(e.type, RagEventType.a2ui);
      expect(e.a2uiMessage!['createSurface']['surfaceId'], 'pick_client_1');
    });

    test('final carries the answer, elapsed and citations', () {
      final e = RagEvent.fromJson({
        'type': 'final',
        'answer': 'Done.',
        'elapsed': 6.4,
        'citations': [
          {'client_id': 7, 'rel': 'a/b.pdf', 'snippet': 's'}
        ],
      });
      expect(e.answer, 'Done.');
      expect(e.elapsed, 6.4);
      expect(e.citations, hasLength(1));
    });

    test('confirm keeps commit_args as an OBJECT', () {
      final e = RagEvent.fromJson({
        'type': 'confirm',
        'name': 'set_task_status',
        'summary': 'Move task #581 to completed.',
        'warnings': ['This notifies the person who allotted it.', '  '],
        'commit_args': {'task_creation_id': 581, 'status': 'completed'},
      });
      expect(e.type, RagEventType.confirm);
      final p = e.proposal!;
      expect(p.name, 'set_task_status');
      expect(p.warnings, ['This notifies the person who allotted it.']);
      expect(p.commitArgs['task_creation_id'], 581);
      expect(p.commitArgs, isA<Map<String, dynamic>>());
    });

    test('unavailable and error', () {
      expect(
        RagEvent.fromJson({'type': 'unavailable', 'reason': 'offline'}).reason,
        'offline',
      );
      expect(
        RagEvent.fromJson({'type': 'error', 'message': 'bad'}).message,
        'bad',
      );
    });

    test('an UNKNOWN type maps to ignore, never to an abort', () {
      for (final t in ['usage', 'ping', 'some_future_event_2027', '']) {
        expect(RagEvent.fromJson({'type': t}).type, RagEventType.ignore,
            reason: t);
      }
      expect(RagEvent.fromJson(const {}).type, RagEventType.ignore);
    });
  });
}
