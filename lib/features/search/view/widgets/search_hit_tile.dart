import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../clients/controller/client_directory.dart';
import '../../../files/view/file_actions_sheet.dart';
import '../../model/search_models.dart';

class SearchHitTile extends ConsumerWidget {
  const SearchHitTile({super.key, required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clientLabel =
        ref.watch(clientDirectoryProvider)[hit.clientId]?.display;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showFileActions(context, file: hit.file, snippet: hit.snippet),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RelevanceBadge(relevance: hit.relevance),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hit.file.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 13, color: theme.colorScheme.outline),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            clientLabel ?? 'Loading client…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontStyle: clientLabel == null
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hit.snippet.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(hit.snippet,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.download_outlined,
                  size: 20, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelevanceBadge extends StatelessWidget {
  const _RelevanceBadge({required this.relevance});
  final int relevance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$relevance%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: scheme.onPrimaryContainer,
          )),
    );
  }
}
