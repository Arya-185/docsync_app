import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// Owns the shared [Dio] client and a persistent cookie jar so the DocSync
/// PHP session (PHPSESSID) survives app restarts. The base URL is swappable
/// at runtime once the user picks / edits a server.
class ApiClient {
  ApiClient._(this.dio, this._jar);

  final Dio dio;
  final PersistCookieJar _jar;

  String _baseUrl = AppConfig.defaultBaseUrl;
  String get baseUrl => _baseUrl;

  static Future<ApiClient> create() async {
    final dir = await getApplicationSupportDirectory();
    final jar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies/'),
    );

    final dio = Dio(BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.answerTimeout,
      // login.php replies with 302 redirects on success/failure; follow them
      // but treat any status < 500 as a non-throwing response so we can inspect.
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (s) => s != null && s < 500,
    ));
    dio.interceptors.add(CookieManager(jar));

    return ApiClient._(dio, jar);
  }

  void setBaseUrl(String url) {
    _baseUrl = _normalize(url);
  }

  /// Full URL for a path relative to the backend root (e.g. '/app/rag_search.php').
  String url(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$_baseUrl$p';
  }

  /// Wipe the session (cookies) on logout.
  Future<void> clearCookies() => _jar.deleteAll();

  /// Read a cookie value for the current base URL host (e.g. the login 'submit'
  /// reason cookie), or null.
  Future<String?> cookieValue(String name) async {
    final cookies = await _jar.loadForRequest(Uri.parse(_baseUrl));
    for (final c in cookies) {
      if (c.name == name) return c.value;
    }
    return null;
  }

  /// The full `name=value; ...` Cookie header for the current base URL, for
  /// handing the session to an out-of-app downloader (system Download Manager).
  Future<String> cookieHeader() async {
    final cookies = await _jar.loadForRequest(Uri.parse(_baseUrl));
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  static String _normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return AppConfig.defaultBaseUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}
