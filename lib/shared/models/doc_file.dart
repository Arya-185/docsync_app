/// A document referenced by a search hit or an answer citation. This is the
/// unit that can be opened / downloaded. Identified by (clientId, rel).
class DocFile {
  final int clientId;
  final String rel;
  final String path;

  const DocFile({
    required this.clientId,
    required this.rel,
    required this.path,
  });

  /// File name (last path segment of rel).
  String get fileName {
    if (rel.isEmpty) return path.isEmpty ? 'file' : path;
    final parts = rel.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? rel : parts.last;
  }

  /// Stable key used to consolidate duplicate hits of the same file.
  String get key => '$clientId::${rel.toLowerCase()}';

  @override
  bool operator ==(Object other) => other is DocFile && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
