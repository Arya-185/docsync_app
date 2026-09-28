import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../model/client_info.dart';
import '../model/client_repository.dart';

final clientRepositoryProvider = Provider<ClientRepository>(
  (ref) => ClientRepository(ref.watch(apiClientProvider)),
);

/// A session-lived cache of client id -> [ClientInfo]. Views call [ensure] with
/// the ids they need; missing ones are batch-fetched and the map updates so the
/// UI can re-render "contact_person - firm_name".
final clientDirectoryProvider =
    NotifierProvider<ClientDirectory, Map<int, ClientInfo>>(ClientDirectory.new);

class ClientDirectory extends Notifier<Map<int, ClientInfo>> {
  final Set<int> _inFlight = {};

  @override
  Map<int, ClientInfo> build() => const {};

  /// Ensure the given ids are resolved. Fetches only ids not already cached or
  /// in flight.
  Future<void> ensure(Iterable<int> ids) async {
    final missing = ids
        .where((id) => id > 0 && !state.containsKey(id) && !_inFlight.contains(id))
        .toSet();
    if (missing.isEmpty) return;

    _inFlight.addAll(missing);
    try {
      final fetched =
          await ref.read(clientRepositoryProvider).fetchByIds(missing.toList());
      if (fetched.isEmpty) return;
      final next = Map<int, ClientInfo>.from(state);
      for (final c in fetched) {
        next[c.id] = c;
      }
      state = next;
    } finally {
      _inFlight.removeAll(missing);
    }
  }

  /// Display label for an id: resolved name, or a neutral fallback until then.
  String label(int id) => state[id]?.display ?? 'Client #$id';
}
