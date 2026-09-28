import 'dart:convert';

import '../../../core/network/api_client.dart';
import 'client_info.dart';

/// Fetches client display info (name + firm) by id from the backend
/// `app/rag_clients.php` endpoint.
class ClientRepository {
  ClientRepository(this._api);
  final ApiClient _api;

  Future<List<ClientInfo>> fetchByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final r = await _api.dio.get(
        _api.url('/app/rag_clients.php'),
        queryParameters: {'ids': ids.join(',')},
      );
      final map = _asMap(r.data);
      if (map == null || map['ok'] != true) return const [];
      return (map['clients'] as List?)
              ?.map((e) => ClientInfo.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final d = jsonDecode(data);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }
}
