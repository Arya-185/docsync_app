import 'doc_file.dart';
import 'util.dart';

/// A citation / source returned with an AI answer.
class Citation {
  final int clientId;
  final String rel;
  final String path;
  final String snippet;

  const Citation({
    required this.clientId,
    required this.rel,
    required this.path,
    this.snippet = '',
  });

  factory Citation.fromJson(Map<String, dynamic> j) => Citation(
        clientId: asInt(j['client_id']),
        rel: (j['rel'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        snippet: (j['snippet'] ?? '').toString(),
      );

  String get key => '$clientId::${rel.toLowerCase()}';

  DocFile toDocFile() => DocFile(clientId: clientId, rel: rel, path: path);
}
