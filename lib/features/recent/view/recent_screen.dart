import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/model/chat_models.dart';

/// Saved conversations, most recent first — voice and typed alike, since both are chat
/// turns. Tapping one opens it in Chat.
class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key, required this.onOpened});

  /// Called after a conversation has been opened, to switch to the Chat tab.
  final VoidCallback onOpened;

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(chatHistoryProvider);
    final sending = ref.watch(chatControllerProvider.select((s) => s.sending));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s2, Ds.s4, Ds.s2),
          child: TextField(
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Search conversations',
              prefixIcon: Icon(Icons.search_rounded),
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.refresh(chatHistoryProvider.future),
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _Message(
                icon: Icons.cloud_off_rounded,
                text: 'Could not load your conversations.',
                action: TextButton(
                  onPressed: () => ref.invalidate(chatHistoryProvider),
                  child: const Text('Try again'),
                ),
              ),
              data: (all) {
                final convos = _filter.isEmpty
                    ? all
                    : all.where((c) => c.title.toLowerCase().contains(_filter)).toList();
                if (convos.isEmpty) {
                  return _Message(
                    icon: Icons.forum_outlined,
                    text: all.isEmpty
                        ? 'No conversations yet.\nAsk something from Voice or Chat.'
                        : 'Nothing matches “$_filter”.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s2, Ds.s4, Ds.s6),
                  itemCount: convos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Ds.s2),
                  itemBuilder: (_, i) => _ConversationTile(
                    c: convos[i],
                    enabled: !sending,
                    onTap: () {
                      ref.read(chatControllerProvider.notifier).openConversation(convos[i].id);
                      widget.onOpened();
                    },
                  ),
                );
              },
            ),
          ),
        ),
        if (sending)
          Padding(
            padding: const EdgeInsets.only(bottom: Ds.s2),
            child: Text('An answer is still running — open it once it finishes.',
                style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.c, required this.enabled, required this.onTap});
  final Conversation c;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: Ds.card(radius: Ds.rChip + 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Ds.rChip + 2),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Ds.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 18, color: Ds.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: c.unseen ? FontWeight.w700 : FontWeight.w500)),
                      if (c.updatedAt.isNotEmpty)
                        Text(c.updatedAt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                /* A dot, not a count or a banner: findable when you look for it,
                   invisible when you are not. */
                if (c.unseen)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.circle, size: 9, color: Ds.blue),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: Ds.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh still works on an empty list.
    return ListView(
      padding: const EdgeInsets.all(Ds.s8),
      children: [
        const SizedBox(height: 60),
        Icon(icon, size: 44, color: Ds.muted),
        const SizedBox(height: Ds.s3),
        Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Ds.muted)),
        if (action != null) Center(child: action),
      ],
    );
  }
}
