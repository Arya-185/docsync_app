import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/tokens.dart';
import '../../../../shared/models/citation.dart';
import '../../../../shared/widgets/file_card.dart';
import '../../../clients/controller/client_directory.dart';
import '../../../files/view/file_actions_sheet.dart';
import '../../controller/chat_controller.dart';
import '../../model/a2ui_actions.dart';
import '../../model/chat_models.dart';
import 'a2ui_surface_view.dart';
import 'confirm_card.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;
    final fg = isUser ? Colors.white : scheme.onSurface;
    // The best source as a full card (Download / Preview / Share), the rest as chips.
    final cites = message.citations;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.8 : 0.9),
        ),
        decoration: BoxDecoration(
          color: isUser ? null : Colors.white,
          gradient: isUser
              ? const LinearGradient(colors: [Ds.blue, Ds.indigo])
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Ds.rCard),
            topRight: const Radius.circular(Ds.rCard),
            bottomLeft: Radius.circular(isUser ? Ds.rCard : 6),
            bottomRight: Radius.circular(isUser ? 6 : Ds.rCard),
          ),
          border: isUser ? null : Border.all(color: Ds.line.withValues(alpha: 0.7)),
          boxShadow: isUser ? null : Ds.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && message.thinking.isNotEmpty) ...[
              _ThinkingPanel(text: message.thinking, streaming: message.streaming),
              const SizedBox(height: 8),
            ],
            _AssistantBody(message: message, foreground: fg),
            if (cites.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Sources',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: fg.withValues(alpha: 0.7))),
              const SizedBox(height: 6),
              FileCard(
                file: cites.first.toDocFile(),
                snippet: cites.first.snippet,
                flat: true,
              ),
              if (cites.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in cites.skip(1)) _CitationChip(citation: c),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The answer text, the A2UI surfaces, and the confirm fallback.
///
/// Stateful for one reason: whether a surface actually RENDERED. Two decisions hang off it and
/// both are wrong if it is assumed:
///
///   * a results list arrives twice, as cards and as the same rows in prose. The text may only
///     be dropped once the cards are really on screen, or a surface that failed to draw takes
///     the rows with it and the bubble is empty.
///   * a proposal arrives twice too, as an A2UI confirm surface and as the legacy `confirm`
///     event. Showing both would be two sets of Confirm buttons for one write.
class _AssistantBody extends ConsumerStatefulWidget {
  const _AssistantBody({required this.message, required this.foreground});

  final ChatMessage message;
  final Color foreground;

  @override
  ConsumerState<_AssistantBody> createState() => _AssistantBodyState();
}

class _AssistantBodyState extends ConsumerState<_AssistantBody> {
  bool _rendered = false;
  String _note = '';
  bool _noteIsError = false;

  /// A commit is in flight, or already succeeded. genui keeps the Confirm button pressable after
  /// a tap, so without this a second tap — or an impatient double tap — POSTs the same write twice.
  bool _committing = false;
  bool _committed = false;

  void _setNote(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _note = text;
      _noteIsError = error;
    });
  }

  Future<void> _handle(A2uiAction action) async {
    switch (action) {
      case SendChat(:final text):
        // The whole contract for these widgets: the answer goes back as an ordinary chat turn.
        _setNote('');
        final sent = await ref.read(chatControllerProvider.notifier).send(text);
        // Refused because an answer is still running: say so rather than ignore the tap.
        if (!sent) _setNote('Still answering — wait for it, or tap Stop first.', error: true);
      case CommitWrite(action: final name, :final args):
        if (_committing || _committed) return;
        _committing = true;
        _setNote('Working…');
        final conv = ref.read(chatControllerProvider).conversationId;
        final res =
            await ref.read(chatRepositoryProvider).commit(name, args, conv: conv);
        _committing = false;
        _committed = res.ok; // a failure leaves the button usable for a retry
        _setNote(res.message, error: !res.ok);
      case CancelWrite():
        _setNote('Cancelled.');
      case ActionFailed(:final message):
        _setNote(message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final theme = Theme.of(context);
    final text = m.visibleContent(rendered: _rendered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (text.isEmpty && m.streaming && m.a2ui.isEmpty)
          const _TypingDots()
        else if (text.isNotEmpty)
          _BubbleText(
              text: text, foreground: widget.foreground, markdown: !m.isUser),
        if (m.a2ui.isNotEmpty)
          A2uiSurfaceView(
            messages: m.a2ui,
            onAction: _handle,
            onRenderedChanged: (r) {
              if (r != _rendered && mounted) setState(() => _rendered = r);
            },
          ),
        // The legacy card, and ONLY when no surface drew one. A confirm-only turn has no prose
        // at all, so this card is the whole message.
        if (m.confirm != null && !_rendered) ConfirmCard(proposal: m.confirm!),
        if (_note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _noteIsError
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// One bubble's text.
///
/// The model writes Markdown — bold, bullet lists, the occasional heading — and it was being
/// shown raw, so answers arrived full of literal asterisks. Rendered with
/// `flutter_markdown_plus`, the maintained continuation of the discontinued `flutter_markdown`,
/// chosen because it pulls in exactly one transitive package (the `markdown` parser) and keeps
/// the text SELECTABLE, which users rely on to copy a figure out of an answer.
///
/// Only the assistant's text goes through it. What a person typed is not Markdown, and running
/// it through a parser would silently reinterpret ordinary punctuation in their own words.
class _BubbleText extends StatelessWidget {
  const _BubbleText({
    required this.text,
    required this.foreground,
    required this.markdown,
  });

  final String text;
  final Color foreground;
  final bool markdown;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(color: foreground, height: 1.35);
    if (!markdown) return SelectableText(text, style: base);

    final theme = Theme.of(context);
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        listBullet: base,
        strong: base.copyWith(fontWeight: FontWeight.w600),
        em: base.copyWith(fontStyle: FontStyle.italic),
        a: base.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        // The model's headings are section labels inside one answer, not page titles; at the
        // theme's own sizes they tower over the surrounding prose in a chat bubble.
        h1: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        h2: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        h3: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        blockquote: base.copyWith(color: foreground.withValues(alpha: 0.8)),
        // A bubble is already padded; the default block spacing doubles it.
        blockSpacing: 6,
      ),
    );
  }
}

class _CitationChip extends ConsumerWidget {
  const _CitationChip({required this.citation});
  final Citation citation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = citation.rel.isNotEmpty
        ? citation.rel.split(RegExp(r'[\\/]')).last
        : 'Source';
    final client = ref.watch(clientDirectoryProvider)[citation.clientId]?.display;
    return ActionChip(
      avatar: const Icon(Icons.description_outlined, size: 16),
      label: Text(
        client == null ? name : '$name · $client',
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () => showFileActions(
        context,
        file: citation.toDocFile(),
        snippet: citation.snippet,
      ),
    );
  }
}

/// The reasoning model's live "thinking" — a collapsible panel above the answer.
/// Auto-expanded while the reasoning streams, then auto-collapsed once the answer is in
/// (unless the user has manually toggled it). Display-only; never persisted.
class _ThinkingPanel extends StatefulWidget {
  const _ThinkingPanel({required this.text, required this.streaming});
  final String text;
  final bool streaming;

  @override
  State<_ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<_ThinkingPanel> {
  late bool _expanded = widget.streaming;
  bool _userToggled = false;

  @override
  void didUpdateWidget(_ThinkingPanel old) {
    super.didUpdateWidget(old);
    // When streaming finishes, collapse — unless the user chose a state themselves.
    if (old.streaming && !widget.streaming && !_userToggled) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              _expanded = !_expanded;
              _userToggled = true;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              child: Row(
                children: [
                  if (widget.streaming)
                    const _PulsingDot()
                  else
                    Icon(Icons.lightbulb_outline, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    widget.streaming ? 'Thinking…' : 'Thoughts',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: muted),
                  ),
                  const Spacer(),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: muted),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SingleChildScrollView(
                reverse: widget.streaming, // keep the newest reasoning in view
                child: Text(
                  widget.text,
                  style: TextStyle(color: muted, fontSize: 12.5, height: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_c),
      child: const CircleAvatar(radius: 4, backgroundColor: Color(0xFFF0AD4E)),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_c.value + i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: CircleAvatar(radius: 3.5, backgroundColor: color),
              ),
            );
          }),
        );
      },
    );
  }
}
