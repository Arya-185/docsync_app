// The Ask AI credits counter ("250 / 500 used"), the app half of the server's AI billing work.
//
// The server sends `credits {scope, used, limit}` after each charged turn (an ADDITIVE SSE event)
// and `GET /app/ai_credits_status.php` returns `{ok, pill}`. Both carry the same object, so one
// parser reads both. A `credits` event must stay an ignore-type event: the turn keeps streaming,
// and no switch over the event types anywhere had to change.
//
// Run: flutter test test/ai_credits_test.dart

import 'package:docsync_app/features/chat/model/ai_credits.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the credits event parses into a counter and keeps the turn streaming', () {
    final ev = RagEvent.fromJson({'type': 'credits', 'scope': 'company', 'used': 250, 'limit': 500});
    expect(ev.type, RagEventType.ignore);
    expect(ev.credits, isNotNull);
    expect(ev.credits!.label, '250 / 500 used');
    expect(ev.credits!.scope, 'company');
  });

  test('a member counter says it is the member\'s own', () {
    final c = AiCredits.tryParse({'scope': 'member', 'used': 23, 'limit': 20})!;
    expect(c.scope, 'member');
    expect(c.tooltip, 'Your AI credits this month');
    expect(c.ratio >= 1, isTrue);
  });

  test('no counter (an uncapped member) and junk parse to null', () {
    expect(AiCredits.tryParse(null), isNull);
    expect(AiCredits.tryParse({'used': '5', 'limit': 10}), isNull);
    expect(RagEvent.fromJson({'type': 'credits'}).credits, isNull);
  });

  test('other benign events carry no counter', () {
    expect(RagEvent.fromJson({'type': 'usage', 'prompt': 3}).credits, isNull);
  });

  test('whole numbers only', () {
    final c = AiCredits.tryParse({'scope': 'company', 'used': 249.0, 'limit': 500})!;
    expect(c.label, '249 / 500 used');
  });
}
