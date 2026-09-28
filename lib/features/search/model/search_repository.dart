import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/config.dart';
import '../../../core/network/api_client.dart';
import 'search_models.dart';

/// Raw result envelope from rag_search.php.
class SearchResponse {
  final bool ok;
  final List<SearchHit> text;
  final List<SearchHit> image;
  final bool indexing;
  final String? state; // offline | slow | disabled | error | not_authenticated
  final String? message;

  const SearchResponse({
    required this.ok,
    this.text = const [],
    this.image = const [],
    this.indexing = false,
    this.state,
    this.message,
  });
}

class SearchRepository {
  SearchRepository(this._api);
  final ApiClient _api;

  Future<SearchResponse> search(String query, {int k = AppConfig.defaultK}) async {
    try {
      final r = await _api.dio.post(
        _api.url('/app/rag_search.php'),
        data: {'query': query, 'k': k},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          receiveTimeout: AppConfig.searchTimeout,
        ),
      );
      final body = _asMap(r.data);
      if (body == null) {
        return const SearchResponse(ok: false, state: 'error', message: 'Unexpected response.');
      }
      if (body['ok'] != true) {
        final state = body.containsKey('offline')
            ? 'offline'
            : body.containsKey('slow')
                ? 'slow'
                : body.containsKey('disabled')
                    ? 'disabled'
                    : (body['error'] ?? 'error').toString();
        return SearchResponse(
          ok: false,
          state: state,
          message: (body['message'] ?? _stateMessage(state)).toString(),
        );
      }

      List<SearchHit> parse(dynamic list) => (list as List?)
              ?.map((e) => SearchHit.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [];

      return SearchResponse(
        ok: true,
        text: parse(body['text']),
        image: parse(body['image']),
        indexing: body['indexing'] == true,
      );
    } on DioException catch (e) {
      return SearchResponse(ok: false, state: 'error', message: _dioMessage(e));
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

  String _stateMessage(String state) {
    switch (state) {
      case 'offline':
        return 'The main PC is offline. Try again in a moment.';
      case 'slow':
        return 'The service is busy indexing. Try again shortly.';
      case 'disabled':
        return 'AI search is not enabled for this company.';
      case 'not_authenticated':
        return 'Your session expired. Please sign in again.';
      default:
        return 'Search failed. Please try again.';
    }
  }

  String _dioMessage(DioException e) {
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'The request timed out. The service may be busy.';
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach the server.';
    }
    return 'Request failed: ${e.message ?? e.type.name}';
  }
}
