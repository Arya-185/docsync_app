import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/providers.dart';
import '../model/a2ui_navigate.dart';
import '../model/task_file_view.dart';

/// A DocSync web page opened from a link card's "Open page" (server M5: `app/open.php`).
///
/// The record pages (a task's history, a client, an invoice, the add-billing-address page) are
/// the web app's own pages behind the web session. The app is already logged in to that same
/// session — the PHPSESSID lives in the dio cookie jar — so the jar's cookies are handed to the
/// WebView before the first load, and open.php does the rest exactly as it does in a browser:
/// checks the session and the client ACL, sets the page's cookies, redirects.
///
/// Navigation stays on the DocSync host. Logout is refused here: it would end the session the
/// app itself is using, and the app has its own sign-out.
class WebPageScreen extends ConsumerStatefulWidget {
  const WebPageScreen({super.key, required this.openUrl});

  /// The card's relative URL, e.g. `open.php?kind=task&id=512` (already checked by [isOpenUrl]).
  final String openUrl;

  static Future<void> push(BuildContext context, String openUrl) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebPageScreen(openUrl: openUrl)),
    );
  }

  @override
  ConsumerState<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends ConsumerState<WebPageScreen> {
  WebViewController? _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final api = ref.read(apiClientProvider);
    final target = Uri.parse(api.url('/app/${widget.openUrl}'));
    final host = target.host;

    // Hand the app's session to the WebView: same cookies, same host, so the page is opened
    // as the signed-in user rather than bounced to the login page.
    final cookies = WebViewCookieManager();
    final header = await api.cookieHeader();
    for (final pair in header.split('; ')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      await cookies.setCookie(WebViewCookie(
        name: pair.substring(0, eq),
        value: pair.substring(eq + 1),
        domain: host,
        path: '/',
      ));
    }

    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) {
            setState(() => _error = 'The page could not be loaded (${e.description}).');
          }
        },
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          if (u == null || u.host != host) return NavigationDecision.prevent;
          if (u.path.endsWith('/logout.php')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Sign out from the app instead — this page shares its session.'),
              ));
            }
            return NavigationDecision.prevent;
          }
          if (_isLogin(u)) {
            _signedOut();
            return NavigationDecision.prevent;
          }
          // The task page's View button: a WebView cannot show a PDF inline, so open the file
          // in the phone's own viewer instead.
          if (isTaskFileViewUrl(u)) {
            _viewFile(u);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        // A server redirect is not always offered to onNavigationRequest; catch it here too.
        onPageStarted: (url) {
          final u = Uri.tryParse(url);
          if (u != null && _isLogin(u)) _signedOut();
        },
      ))
      // The task page reports failures with alert() ("Could not save that.") and may ask with
      // confirm(). An Android WebView drops both silently unless the app draws them.
      ..setOnJavaScriptAlertDialog((req) => _alert(req.message))
      ..setOnJavaScriptConfirmDialog((req) => _confirm(req.message))
      ..loadRequest(target);
    if (mounted) setState(() => _controller = c);
  }

  static bool _isLogin(Uri u) => u.path.endsWith('/login.php');

  Future<void> _alert(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('OK'))],
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('OK')),
        ],
      ),
    );
    return ok ?? false;
  }

  bool _viewing = false;

  Future<void> _viewFile(Uri u) async {
    if (_viewing) return; // one file at a time
    _viewing = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Opening the file from the office PC…'),
      duration: Duration(seconds: 2),
    ));
    try {
      final err = await openTaskFile(ref.read(apiClientProvider), u);
      if (err != null && mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(err)));
      }
    } finally {
      _viewing = false;
    }
  }

  bool _closing = false;

  /// The web sent this page to its login screen: the session is no longer good for web pages
  /// (signed in again elsewhere — the web allows one session per user). Never show a login form
  /// inside the app; close and say why.
  void _signedOut() {
    if (_closing || !mounted) return;
    _closing = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(const SnackBar(
      content: Text('The web page needs a fresh sign-in (this account signed in somewhere else).'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        // Always leaves the screen; the system back button walks the page's history first.
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(pageTitle(widget.openUrl)),
        actions: [
          if (c != null)
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() => _error = null);
                c.reload();
              },
            ),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              )
            : null,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : PopScope(
                  canPop: false,
                  // Back walks the page's own history first, then leaves the screen.
                  onPopInvokedWithResult: (didPop, _) async {
                    if (didPop) return;
                    if (await c.canGoBack()) {
                      await c.goBack();
                    } else if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: WebViewWidget(controller: c),
                ),
    );
  }
}
