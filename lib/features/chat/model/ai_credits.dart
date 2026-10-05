import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// The Ask AI credits counter ("250 / 500 used"), mirroring the web chat.
///
/// The server sends it two ways: `GET /app/ai_credits_status.php` (`{ok, pill}`) when the app opens,
/// and the additive `credits` SSE event after every turn is charged. Whole numbers only. The firm
/// owner sees the firm's credits ([scope] 'company'); a member the owner capped sees their own
/// limit ('member'); everyone else gets `pill: null` and the app shows nothing.
class AiCredits {
  final String scope; // 'company' | 'member'
  final int used;
  final int limit;

  const AiCredits({required this.scope, required this.used, required this.limit});

  /// From the `pill` object or the `credits` event. Null when it is not a usable counter.
  static AiCredits? tryParse(dynamic j) {
    if (j is! Map) return null;
    final used = j['used'], limit = j['limit'];
    if (used is! num || limit is! num) return null;
    return AiCredits(
      scope: j['scope'] == 'member' ? 'member' : 'company',
      used: used.toInt(),
      limit: limit.toInt(),
    );
  }

  String get label => '$used / $limit used';

  /// 0..1+ — 0.8 turns the pill amber, 1 red.
  double get ratio => limit > 0 ? used / limit : 1;

  String get tooltip => scope == 'member' ? 'Your AI credits this month' : "Your firm's AI credits this month";
}

/// The counter on screen. Loaded on first watch, then set by the chat controller from `credits`.
final aiCreditsProvider = NotifierProvider<AiCreditsController, AiCredits?>(AiCreditsController.new);

class AiCreditsController extends Notifier<AiCredits?> {
  @override
  AiCredits? build() {
    Future.microtask(refresh);
    return null;
  }

  void set(AiCredits? c) => state = c;

  /// A convenience, never an error: any failure leaves the counter as it was.
  Future<void> refresh() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.dio.get(api.url('/app/ai_credits_status.php'));
      dynamic body = r.data;
      if (body is String) body = jsonDecode(body);
      if (body is Map && body['ok'] == true) state = AiCredits.tryParse(body['pill']);
    } catch (_) {}
  }
}
