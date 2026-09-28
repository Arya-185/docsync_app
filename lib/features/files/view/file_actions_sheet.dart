import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/doc_file.dart';
import '../../clients/controller/client_directory.dart';
import '../controller/download_controller.dart';
import '../controller/file_open_controller.dart';

/// Show the file actions sheet (details + download) for a document.
void showFileActions(
  BuildContext context, {
  required DocFile file,
  String snippet = '',
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _FileActionsSheet(file: file, snippet: snippet),
  );
}

class _FileActionsSheet extends ConsumerWidget {
  const _FileActionsSheet({required this.file, required this.snippet});

  final DocFile file;
  final String snippet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dir = ref.watch(clientDirectoryProvider);
    final clientLabel = dir[file.clientId]?.display ?? 'Client #${file.clientId}';
    final dl = ref.watch(downloadControllerProvider
        .select((m) => m[file.key] ?? const DownloadState()));
    final ctrl = ref.read(downloadControllerProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.description_outlined,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(file.fileName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _row(theme, Icons.person_outline, clientLabel),
          const SizedBox(height: 6),
          _row(theme, Icons.folder_outlined, file.rel.isEmpty ? '—' : file.rel),
          if (snippet.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Excerpt', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(snippet, style: theme.textTheme.bodyMedium),
            ),
          ],
          const SizedBox(height: 20),
          _actionArea(context, theme, dl, ctrl),
          const SizedBox(height: 10),
          _openRow(context, ref),
        ],
      ),
    );
  }

  Widget _actionArea(BuildContext context, ThemeData theme, DownloadState dl,
      DownloadController ctrl) {
    switch (dl.phase) {
      case DownloadPhase.running:
        final pct = dl.progress >= 0 ? (dl.progress * 100).round() : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Downloading…', style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(pct != null ? '$pct%' : '',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: dl.progress >= 0 ? dl.progress : null,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text('Saving to your Downloads folder — see the notification for progress.',
                style: theme.textTheme.bodySmall),
          ],
        );
      case DownloadPhase.complete:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.download_done, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dl.savedPath != null && dl.savedPath!.isNotEmpty
                          ? 'Saved to Downloads'
                          : 'Saved to your Downloads folder',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => ctrl.start(file),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download again'),
              ),
            ),
          ],
        );
      case DownloadPhase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(dl.error ?? 'Download failed.',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => ctrl.start(file),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ),
          ],
        );
      case DownloadPhase.idle:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: () => ctrl.start(file),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download to phone'),
          ),
        );
    }
  }

  /// Preview and Share work from a private cached copy, so they never depend on the
  /// public download having happened.
  Widget _openRow(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(fileOpenControllerProvider.select((m) => m[file.key]));
    final open = ref.read(fileOpenControllerProvider.notifier);

    Future<void> run(Future<String?> Function() op) async {
      final err = await op();
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }

    Widget button(FileOp op, IconData icon, String label, Future<String?> Function() fn) {
      return Expanded(
        child: SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: busy != null ? null : () => run(fn),
            icon: busy == op
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 18),
            label: Text(label),
          ),
        ),
      );
    }

    return Row(
      children: [
        button(FileOp.preview, Icons.visibility_outlined, 'Preview',
            () => open.preview(file)),
        const SizedBox(width: 10),
        button(FileOp.share, Icons.ios_share_rounded, 'Share', () => open.share(file)),
      ],
    );
  }

  Widget _row(ThemeData theme, IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(text, style: theme.textTheme.bodyMedium)),
        ],
      );
}
