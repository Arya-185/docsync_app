import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/doc_file.dart';

class DownloadException implements Exception {
  final String message;
  DownloadException(this.message);
  @override
  String toString() => message;
}

/// Downloads a document with `background_downloader`, which shows a native
/// sticky progress notification (with percentage) while running and moves the
/// finished file into the phone's public Downloads folder.
///
/// The DocSync endpoint reads the client id from the shared PHP session
/// (`cf_client_id`), so we first set it (an in-app GET on the same session
/// cookie) and then run the task carrying that same PHPSESSID cookie. The whole
/// "set client -> download" pair is awaited under an async lock so downloads for
/// different clients can't race on that shared session field.
class DownloadRepository {
  DownloadRepository(this._api);
  final ApiClient _api;

  Future<void> _lock = Future.value();
  bool _notifConfigured = false;

  /// Download [file]; reports 0..1 progress via [onProgress] (also shown in the
  /// notification). Returns the saved public path (may be null if the OS didn't
  /// report one). Throws [DownloadException].
  Future<String?> download(DocFile file, {void Function(double p)? onProgress}) =>
      _serialized(() => _run(file, onProgress));

  /// Fetch [file] into the app's private cache for Preview/Share, reusing a cached copy
  /// unless [refresh]. Not a public download: no notification, nothing in Downloads.
  /// Runs under the same lock as [download] because both move `cf_client_id`.
  Future<File> fetchToCache(DocFile file, {bool refresh = false}) =>
      _serialized(() => _fetchToCache(file, refresh));

  Future<T> _serialized<T>(Future<T> Function() body) {
    final op = _lock.then((_) => body());
    _lock = op.then((_) {}, onError: (_) {});
    return op;
  }

  Future<File> _fetchToCache(DocFile file, bool refresh) async {
    final root = await getTemporaryDirectory();
    // One folder per client so two clients' same-named files never overwrite each other.
    final dir = Directory('${root.path}${Platform.pathSeparator}files'
        '${Platform.pathSeparator}${file.clientId}');
    final out = File('${dir.path}${Platform.pathSeparator}${file.fileName}');
    if (!refresh && await out.exists() && await out.length() > 0) return out;
    await dir.create(recursive: true);

    await _selectClient(file);
    final part = File('${out.path}.part');
    try {
      final r = await _api.dio.download(
        _api.url('/app/client_files_action.php'),
        part.path,
        queryParameters: {'action': 'download', 'p': file.rel},
        options: Options(
          receiveTimeout: AppConfig.downloadTimeout,
          validateStatus: (s) => s != null && s < 500 && s != 404 && s != 403,
        ),
      );
      final type = r.headers.value(Headers.contentTypeHeader) ?? '';
      // The endpoint answers a lost session with the HTML login page, not an error status.
      if (type.contains('text/html') && !file.fileName.toLowerCase().endsWith('.html')) {
        throw DownloadException('Your session expired. Please sign in again.');
      }
      return await part.rename(out.path);
    } on DioException catch (e) {
      switch (e.response?.statusCode) {
        case 403:
          throw DownloadException('You do not have download access.');
        case 404:
          throw DownloadException('File not found on the host.');
        case 503:
          throw DownloadException('The file host (main PC) is offline.');
      }
      throw DownloadException(_dioMessage(e));
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  /// Step 1 of every fetch: set cf_client_id in the session (the endpoint reads it from there).
  Future<void> _selectClient(DocFile file) async {
    try {
      await _api.dio.get(
        _api.url('/app/client_files.php'),
        queryParameters: {'client_id': file.clientId},
        options: Options(receiveTimeout: AppConfig.connectTimeout),
      );
    } on DioException catch (e) {
      throw DownloadException(_dioMessage(e));
    }
  }

  Future<String?> _run(DocFile file, void Function(double)? onProgress) async {
    _configureNotifications();
    // Best-effort: ask for the notification permission (Android 13+).
    try {
      await FileDownloader().permissions.request(PermissionType.notifications);
    } catch (_) {}

    await _selectClient(file);

    final uri = Uri.parse(_api.url('/app/client_files_action.php')).replace(
      queryParameters: {'action': 'download', 'p': file.rel},
    );
    final cookie = await _api.cookieHeader();
    if (cookie.isEmpty) {
      throw DownloadException('Your session expired. Please sign in again.');
    }

    final task = DownloadTask(
      url: uri.toString(),
      filename: file.fileName,
      headers: {'Cookie': cookie, 'User-Agent': 'DocSyncApp (Android)'},
      updates: Updates.statusAndProgress,
      retries: 0,
    );

    final TaskStatusUpdate result;
    try {
      result = await FileDownloader().download(
        task,
        onProgress: (p) {
          if (p >= 0 && p <= 1) onProgress?.call(p);
        },
      );
    } catch (e) {
      throw DownloadException('Download failed: $e');
    }

    switch (result.status) {
      case TaskStatus.complete:
        // Move from the app-private dir into the public Downloads folder.
        final path = await FileDownloader()
            .moveToSharedStorage(task, SharedStorage.downloads);
        return path;
      case TaskStatus.notFound:
        throw DownloadException('File not found on the host.');
      case TaskStatus.failed:
        final ex = result.exception;
        if (ex is TaskHttpException) {
          switch (ex.httpResponseCode) {
            case 403:
              throw DownloadException('You do not have download access.');
            case 503:
              throw DownloadException('The file host (main PC) is offline.');
            case 404:
              throw DownloadException('File not found on the host.');
          }
        }
        throw DownloadException(ex?.description ?? 'Download failed.');
      case TaskStatus.canceled:
        throw DownloadException('Download canceled.');
      default:
        throw DownloadException('Download failed.');
    }
  }

  void _configureNotifications() {
    if (_notifConfigured) return;
    FileDownloader().configureNotification(
      running: const TaskNotification('{filename}', 'Downloading… {progress}'),
      complete: const TaskNotification('{filename}', 'Saved to Downloads'),
      error: const TaskNotification('{filename}', 'Download failed'),
      progressBar: true,
    );
    _notifConfigured = true;
  }

  String _dioMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The request timed out.';
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Cannot reach the server.';
      default:
        return 'Download failed: ${e.message ?? e.type.name}';
    }
  }
}
