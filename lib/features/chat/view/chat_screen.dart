import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../../shared/widgets/mic_button.dart';
import '../controller/chat_controller.dart';
import 'widgets/activity_trail.dart';
import 'widgets/chat_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /* A turn keeps running on the server while the phone is locked or the app is in the
     background, and Android may drop the socket meanwhile. Coming back picks it up —
     the answer that landed, or the turn still in progress — instead of leaving a question
     with nothing under it until the chat is reopened by hand. */
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      ref.read(chatControllerProvider.notifier).resync();
    }
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
    if (ref.read(chatControllerProvider).sending) {
      // Keep what they typed; say why nothing happened instead of dropping the tap.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Still answering — tap Stop to interrupt.'),
      ));
      return;
    }
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
    if (!hasMessages) return const SizedBox(height: 4);

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8),
      child: Row(
        children: [
          const Spacer(),
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
    final busy = ref.watch(
        chatControllerProvider.select((s) => (sending: s.sending, stopping: s.stopping)));
    return _InputBar(
      controller: controller,
      sending: busy.sending,
      stopping: busy.stopping,
      onSend: onSend,
      onStop: () => ref.read(chatControllerProvider.notifier).stop(),
    );
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
        padding: const EdgeInsets.all(Ds.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                gradient: Ds.orbGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 30, color: Colors.white),
            ),
            const SizedBox(height: Ds.s4),
            Text('Ask about your clients', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Documents, tasks, invoices, reminders — type or tap the mic.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Ds.muted)),
            const SizedBox(height: Ds.s6),
            for (final e in examples)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Ds.rChip),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Ds.rChip),
                    onTap: () => onExample(e),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Ds.rChip),
                        border: Border.all(color: Ds.line),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.north_east_rounded, size: 16, color: Ds.blue),
                          const SizedBox(width: 10),
                          Expanded(child: Text(e, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                  ),
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
    required this.stopping,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool sending;
  final bool stopping;
  final void Function([String?]) onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Ds.rPill),
          boxShadow: Ds.pillShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MicButton(controller: controller, enabled: !sending),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask anything about your clients…',
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 4),
            /* While a turn runs the send button IS the stop button: the one place the thumb
               already is. "Stopping…" covers the gap until the agent reaches its next check. */
            if (sending)
              Tooltip(
                message: stopping ? 'Stopping…' : 'Stop',
                child: IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Ds.ink),
                  onPressed: stopping ? null : onStop,
                  icon: stopping
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.stop_rounded, color: Colors.white),
                ),
              )
            else
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Ds.blue),
                onPressed: () => onSend(),
                icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}
