import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/chat_controller.dart';

/// Bottom sheet listing the user's saved conversations. Tapping one loads it.
void showChatHistory(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _HistorySheet(),
  );
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(chatHistoryProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 8),
                  Text('Chat history', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ref.invalidate(chatHistoryProvider),
                  ),
                ],
              ),
            ),
            Flexible(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Could not load history.')),
                ),
                data: (convos) {
                  if (convos.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('No saved chats yet.',
                            style: theme.textTheme.bodyMedium),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: convos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = convos[i];
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: c.unseen
                                ? const TextStyle(fontWeight: FontWeight.w600)
                                : null),
                        /* A dot, not a count or a banner: findable when you look for it,
                           invisible when you are not. */
                        trailing: c.unseen
                            ? Icon(Icons.circle,
                                size: 8,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        subtitle: c.updatedAt.isEmpty
                            ? null
                            : Text(c.updatedAt,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(context);
                          ref
                              .read(chatControllerProvider.notifier)
                              .openConversation(c.id);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
