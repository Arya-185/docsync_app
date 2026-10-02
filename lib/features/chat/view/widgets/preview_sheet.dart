import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../controller/chat_controller.dart';
import '../../model/a2ui_actions.dart';
import '../web_page_screen.dart';
import 'a2ui_docsync_catalog.dart';

/// Preview (server M3): the invoice or email a card would create or send — or an invoice that
/// exists — drawn in a sheet over the chat, so the user never leaves the conversation to check it.
///
/// The app half of the web's Preview popup. `ai_preview.php` returns a whole, self-contained
/// document (the logo inlined as a data URI), so it is loaded as a string and the WebView needs
/// no session, no network and no JavaScript: scripts are off and every navigation is refused,
/// the same promise as the web's `<iframe sandbox="">`. Nothing here can write anything.
class PreviewSheet extends ConsumerStatefulWidget {
  const PreviewSheet({super.key, required this.request});

  final PreviewRequest request;

  static Future<void> show(BuildContext context, PreviewRequest request) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: PreviewSheet(request: request),
      ),
    );
  }

  @override
  ConsumerState<PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends ConsumerState<PreviewSheet> {
  String _title = '';
  String? _error;
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    _title = widget.request.kind == 'invoice' ? 'Invoice' : 'Preview';
    _load();
  }

  Future<void> _load() async {
    final res = await ref.read(chatRepositoryProvider).preview(widget.request.fields);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _error = res.message);
      return;
    }
    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0xFFF4F6FA))
      ..enableZoom(true)
      // The document is drawn from a string: there is nothing to navigate TO. A link inside it
      // must not turn this sheet into a browser.
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) => req.url.startsWith('about:') || req.url.startsWith('data:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ));
    await web.loadHtmlString(res.html);
    if (!mounted) return;
    setState(() {
      _title = res.title.isEmpty ? _title : res.title;
      _web = web;
    });
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.request.kind == 'invoice';
    return Column(
      children: [
        _SheetHead(title: _title),
        Expanded(
          child: Container(
            color: const Color(0xFFF4F6FA),
            child: _error != null
                ? _Message(_error!, error: true)
                : _web == null
                    ? const _Message('Drawing the preview…', busy: true)
                    : WebViewWidget(controller: _web!),
          ),
        ),
        if (invoice)
          _SheetFoot(children: [
            OutlinedButton(
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                WebPageScreen.push(nav.context, 'open.php?kind=invoice&id=${widget.request.id}');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: A2.indigo,
                side: const BorderSide(color: A2.indigo),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Open full page'),
            ),
          ]),
      ],
    );
  }
}

/// The sheet's title bar: a grab handle, the title in navy, and a close button.
class _SheetHead extends StatelessWidget {
  const _SheetHead({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: A2.line))),
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 2),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: A2.line, borderRadius: BorderRadius.circular(2)),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: A2.navy),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: A2.muted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetFoot extends StatelessWidget {
  const _SheetFoot({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: A2.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.error = false, this.busy = false});
  final String text;
  final bool error;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy) ...[
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 14, color: error ? const Color(0xFFB42318) : const Color(0xFF475467)),
            ),
          ),
        ],
      ),
    );
  }
}
