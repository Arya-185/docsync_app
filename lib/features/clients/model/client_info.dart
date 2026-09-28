import '../../../shared/models/util.dart';

/// A client's display identity, resolved from client_list via rag_clients.php.
class ClientInfo {
  final int id;
  final String contactPerson;
  final String firmName;

  const ClientInfo({
    required this.id,
    required this.contactPerson,
    required this.firmName,
  });

  factory ClientInfo.fromJson(Map<String, dynamic> j) => ClientInfo(
        id: asInt(j['id']),
        contactPerson: (j['contact_person'] ?? '').toString().trim(),
        firmName: (j['firm_name'] ?? '').toString().trim(),
      );

  /// "client name - firm name" (falls back gracefully when a part is missing).
  String get display {
    final hasPerson = contactPerson.isNotEmpty;
    final hasFirm = firmName.isNotEmpty;
    if (hasPerson && hasFirm) return '$contactPerson - $firmName';
    if (hasPerson) return contactPerson;
    if (hasFirm) return firmName;
    return 'Client #$id';
  }
}
