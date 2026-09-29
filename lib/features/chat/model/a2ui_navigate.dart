/// `docsync.navigate` — the "Open page" button on an Ask AI link card.
///
/// On the web the button opens `open.php?kind=…&id=…`, which checks the session and the
/// client ACL, sets the cookies the app's list pages set, and lands on the record's page
/// (a task's history, a client, an invoice, the page where a missing billing address is added).
/// The app opens the same URL in an in-app WebView that shares its session
/// (`view/web_page_screen.dart`).
///
/// The URL check is the same allow-list as `isOpenUrl()` in the server's
/// `web/src/a2ui-docsync.js` — anything else is refused, whatever the surface says.
library;

final RegExp _openUrl = RegExp(
    r'^open\.php\?kind=(task|client|client_edit|client_address|client_files|invoice)&id=([1-9]\d{0,9})$');

/// True for the only URLs a link card may carry.
bool isOpenUrl(Object? url) => url is String && _openUrl.hasMatch(url);

/// The title of the screen a link card opens.
String pageTitle(String url) {
  final m = _openUrl.firstMatch(url);
  final id = m?.group(2) ?? '';
  return switch (m?.group(1) ?? '') {
    'task' => 'Task #$id',
    'invoice' => 'Invoice',
    'client_address' => 'Billing address',
    'client_edit' => 'Client details',
    'client_files' => 'Client files',
    _ => 'Client',
  };
}
