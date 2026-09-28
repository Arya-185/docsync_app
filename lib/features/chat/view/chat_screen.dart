import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/mic_button.dart';
import '../controller/chat_controller.dart';
import 'widgets/activity_trail.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/history_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 160,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? preset]) {
    final text = preset ?? _input.text;
    if (text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(text);
    _scrollToEnd();
  }

  /* Each section watches only what it draws.

     This was one `ref.watch(chatControllerProvider)` over the whole state, so every streamed
     token rebuilt the header, the trail and the input bar along with the message list — and
     the activity trail made it materially worse, because a busy turn now pushes state on
     every STEP as well as every token. The transcript still rebuilds per token, which it has
     to; nothing else does. */
  @override
  Widget build(BuildContext context) {
    ref.listen(chatControllerProvider, (_, _) => _scrollToEnd());

    return Column(
      children: [
        const _ChatHeader(),
        Expanded(child: _Transcript(scroll: _scroll, onExample: _send)),
        const _TrailSection(),
        _InputSection(controller: _input, onSend: _send),
      ],
    );
  }
}

class _ChatHeader extends ConsumerWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sending = ref.watch(chatControllerProvider.select((s) => s.sending));
    final hasMessages =
        ref.watch(chatControllerProvider.select((s) => s.messages.isNotEmpty));

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: sending ? null : () => showChatHistory(context),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('History'),
          ),
          const Spacer(),
          if (hasMessages)
            TextButton.icon(
              onPressed: sending
                  ? null
                  : () => ref.read(chatControllerProvider.notifier).newChat(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New chat'),
            ),
        ],
      ),
    );
  }
}

class _Transcript extends ConsumerWidget {
  const _Transcript({required this.scroll, required this.onExample});

  final ScrollController scroll;
  final void Function(String) onExample;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages =
        ref.watch(chatControllerProvider.select((s) => s.messages));
    if (messages.isEmpty) return _EmptyState(onExample: onExample);
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (_, i) => ChatBubble(message: messages[i]),
    );
  }
}

class _TrailSection extends ConsumerWidget {
  const _TrailSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One select over the three fields together: they change as a unit, so three separate
    // watches would rebuild this three times for a single step event.
    final trail = ref.watch(chatControllerProvider
        .select((s) => (steps: s.trail, done: s.trailDone, elapsed: s.elapsed)));
    return ActivityTrail(
      steps: trail.steps,
      done: trail.done,
      elapsed: trail.elapsed,
    );
  }
}

class _InputSection extends ConsumerWidget {
  const _InputSection({required this.controller, required this.onSend});

  final TextEditingController controller;
  final void Function([String?]) onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sending = ref.watch(chatControllerProvider.select((s) => s.sending));
    return _InputBar(controller: controller, sending: sending, onSend: onSend);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onExample});
  final void Function(String) onExample;

  @override
  Widget build(BuildContext context) {
    const examples = [
      'Summarise the latest document for a client',
      'Which clients have pending GST filings?',
      'Find the agreement mentioning a renewal date',
    ];
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Ask about your documents',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Type a question or tap the mic to speak.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 20),
            for (final e in examples)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => onExample(e),
                  child: Text(e, textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final void Function([String?]) onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MicButton(controller: controller, filled: true, enabled: !sending),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Ask a question…',
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: sending ? null : () => onSend(),
                icon: sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
