import '../../../shared/models/doc_file.dart';
import '../../../shared/models/util.dart';

/// A single document-search result.
class SearchHit {
  final int clientId;
  final String rel;
  final String path;
  final String snippet;
  final int relevance; // 0-100 %
  final String modality; // text | image

  const SearchHit({
    required this.clientId,
    required this.rel,
    required this.path,
    required this.snippet,
    required this.relevance,
    this.modality = 'text',
  });

  factory SearchHit.fromJson(Map<String, dynamic> j) => SearchHit(
        clientId: asInt(j['client_id']),
        rel: (j['rel'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        snippet: (j['snippet'] ?? '').toString(),
        relevance: asInt(j['relevance']),
        modality: (j['modality'] ?? 'text').toString(),
      );

  DocFile get file => DocFile(clientId: clientId, rel: rel, path: path);

  /// Consolidation key: same client + same file (case-insensitive).
  String get key => '$clientId::${rel.toLowerCase()}';

  SearchHit copyWith({int? relevance, String? snippet}) => SearchHit(
        clientId: clientId,
        rel: rel,
        path: path,
        snippet: snippet ?? this.snippet,
        relevance: relevance ?? this.relevance,
        modality: modality,
      );
}

enum SearchPhase { initial, loading, success, failure }

/// Immutable state for the search screen.
class SearchState {
  final SearchPhase phase;
  final List<SearchHit> hits; // already consolidated + capped
  final bool indexing;
  final String? message;

  const SearchState({
    this.phase = SearchPhase.initial,
    this.hits = const [],
    this.indexing = false,
    this.message,
  });

  SearchState copyWith({
    SearchPhase? phase,
    List<SearchHit>? hits,
    bool? indexing,
    String? message,
  }) =>
      SearchState(
        phase: phase ?? this.phase,
        hits: hits ?? this.hits,
        indexing: indexing ?? this.indexing,
        message: message,
      );
}
