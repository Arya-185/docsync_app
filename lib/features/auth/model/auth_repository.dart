import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

/// Result of a login attempt: null [error] means success.
class LoginOutcome {
  final bool success;
  final String? error;
  const LoginOutcome.ok()
      : success = true,
        error = null;
  const LoginOutcome.fail(this.error) : success = false;
}

/// Talks to the existing DocSync `login.php` and verifies the session.
class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  ApiClient get api => _api;

  Future<LoginOutcome> login({
    required String cmpAbbr,
    required String email,
    required String password,
  }) async {
    await _api.clearCookies(); // drop any stale session first

    try {
      await _api.dio.post(
        _api.url('/login.php'),
        data: {
          'email': email,
          'password': password,
          'cmp_abbr': cmpAbbr,
          'submit': 'Login',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      return LoginOutcome.fail(_dioMessage(e));
    }

    // login.php never returns JSON — verify by hitting a session-gated endpoint.
    if (await verifySession()) return const LoginOutcome.ok();

    final reason = await _api.cookieValue('submit');
    return LoginOutcome.fail(_reasonMessage(reason));
  }

  Future<void> logout() => _api.clearCookies();

  /// True if the current session cookie is still live.
  Future<bool> verifySession() async {
    try {
      final r = await _api.dio.get(
        _api.url('/app/rag_conversations.php'),
        queryParameters: {'action': 'list'},
      );
      final body = r.data;
      if (body is Map && body['ok'] == true) return true;
      if (body is String && body.contains('"ok":true')) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  String _reasonMessage(String? reason) {
    switch (reason) {
      case 'wrong_pass':
        return 'Incorrect password.';
      case 'wrong_company':
        return 'Unknown company code.';
      case 'company_disabled':
        return 'This company is disabled.';
      case 'expired_subscription':
        return 'Subscription expired.';
      case null:
      case '':
        return 'Login failed. Check your details and try again.';
      default:
        return 'Login failed ($reason).';
    }
  }

  String _dioMessage(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server. Check the URL and your connection.';
    }
    return 'Login request failed: ${e.message ?? e.type.name}';
  }
}
