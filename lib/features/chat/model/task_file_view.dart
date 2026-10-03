import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config.dart';
import '../../../core/network/api_client.dart';

/// The task page's "View" button (server doc match v2: `doc_readiness.php?action=view`).
///
/// On the web it opens the matched client file in a new tab, streamed inline from the office PC.
/// An Android WebView cannot show a PDF inline (it would draw a blank page), so the task page
/// opened in the app hands that link here instead: the file is fetched with the app's own
/// session and opened in whatever app on the phone handles its type.
///
/// The server runs every gate (task access, file rights, same client, PC online) and answers a
/// refusal with a short HTML page; that page's sentence is returned as the error to show.
bool isTaskFileViewUrl(Uri u) =>
    u.path.endsWith('/doc_readiness.php') &&
    u.queryParameters['action'] == 'view' &&
    RegExp(r'^[1-9]\d{0,9}$').hasMatch(u.queryParameters['task_id'] ?? '') &&
    RegExp(r'^[1-9]\d{0,9}$').hasMatch(u.queryParameters['file_id'] ?? '');

/// Fetch and open. Returns an error to show, or null on success.
Future<String?> openTaskFile(ApiClient api, Uri link) async {
  if (!isTaskFileViewUrl(link)) return 'That link cannot be opened here.';
  final taskId = link.queryParameters['task_id']!;
  final fileId = link.queryParameters['file_id']!;
  try {
    final r = await api.dio.get<List<int>>(
      api.url('/app/doc_readiness.php'),
      queryParameters: {'action': 'view', 'task_id': taskId, 'file_id': fileId},
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: AppConfig.downloadTimeout,
        validateStatus: (s) => s != null,
      ),
    );
    final type = r.headers.value(Headers.contentTypeHeader) ?? '';
    final body = r.data ?? const <int>[];
    if (r.statusCode == 401) return 'Your session expired. Please sign in again.';
    if (r.statusCode != 200 || type.contains('text/html') || type.contains('application/json')) {
      return refusalText(String.fromCharCodes(body)) ??
          'The file could not be opened (${r.statusCode}).';
    }
    final name = fileNameFrom(r.headers.value('content-disposition')) ?? 'document';
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}task_files'
        '${Platform.pathSeparator}$taskId-$fileId');
    await dir.create(recursive: true);
    final out = File('${dir.path}${Platform.pathSeparator}$name');
    await out.writeAsBytes(body, flush: true);
    final o = await OpenFilex.open(out.path);
    switch (o.type) {
      case ResultType.done:
        return null;
      case ResultType.noAppToOpen:
        return 'No app on this phone can open $name.';
      default:
        return o.message.isEmpty ? 'Could not open the file.' : o.message;
    }
  } on DioException catch (e) {
    return e.type == DioExceptionType.receiveTimeout
        ? 'The office PC took too long to send the file.'
        : 'The file could not be fetched. Check the connection and try again.';
  } catch (_) {
    return 'Could not open the file.';
  }
}

/// `inline; filename="Form 16.pdf"` -> `Form 16.pdf`, made safe as a file name.
String? fileNameFrom(String? disposition) {
  if (disposition == null) return null;
  final m = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(disposition);
  if (m == null) return null;
  final name = m.group(1)!.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return name.isEmpty || name == '.' || name == '..' ? null : name;
}

/// The sentence in the server's refusal page (`docready_page`), or a JSON error, or null.
String? refusalText(String body) {
  final p = RegExp(r'<p>(.*?)</p>', dotAll: true).firstMatch(body);
  if (p != null) {
    return p
        .group(1)!
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .trim();
  }
  if (body.contains('not_authenticated')) return 'Your session expired. Please sign in again.';
  return null;
}
