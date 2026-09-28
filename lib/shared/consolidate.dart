/// Consolidate repeated items into one (by [keyOf]), rank by [scoreOf] desc,
/// and cap to [limit]. Duplicate entries are combined with [merge] (e.g. keep
/// the highest relevance and the longest snippet).
List<T> consolidateTop<T>(
  Iterable<T> items, {
  required String Function(T) keyOf,
  required num Function(T) scoreOf,
  required T Function(T existing, T incoming) merge,
  int limit = 5,
}) {
  final byKey = <String, T>{};
  for (final item in items) {
    final k = keyOf(item);
    final existing = byKey[k];
    byKey[k] = existing == null ? item : merge(existing, item);
  }
  final list = byKey.values.toList()
    ..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
  return list.length > limit ? list.sublist(0, limit) : list;
}
