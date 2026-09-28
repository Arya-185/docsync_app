import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import '../../../shared/consolidate.dart';
import '../../clients/controller/client_directory.dart';
import '../model/search_models.dart';
import '../model/search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(apiClientProvider)),
);

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state = state.copyWith(phase: SearchPhase.loading, message: null);

    final resp = await ref.read(searchRepositoryProvider).search(q);
    if (!resp.ok) {
      state = SearchState(phase: SearchPhase.failure, message: resp.message);
      return;
    }

    // Consolidate duplicate hits of the same file, rank by relevance, cap to 5.
    final consolidated = consolidateTop<SearchHit>(
      [...resp.text, ...resp.image],
      keyOf: (h) => h.key,
      scoreOf: (h) => h.relevance,
      merge: (a, b) => a.copyWith(
        relevance: a.relevance >= b.relevance ? a.relevance : b.relevance,
        snippet: b.snippet.length > a.snippet.length ? b.snippet : a.snippet,
      ),
      limit: AppConfig.maxResults,
    );

    state = SearchState(
      phase: SearchPhase.success,
      hits: consolidated,
      indexing: resp.indexing,
    );

    // Resolve client names/firms for the shown hits.
    ref.read(clientDirectoryProvider.notifier).ensure(
          consolidated.map((h) => h.clientId).toSet(),
        );
  }

  void clear() => state = const SearchState();
}
