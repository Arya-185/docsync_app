import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../features/clients/controller/client_directory.dart';
import '../../features/files/controller/download_controller.dart';
import '../../features/files/controller/file_open_controller.dart';
import '../../features/files/view/file_actions_sheet.dart';
import '../models/doc_file.dart';

/// A document as a card: type badge, name, "client – firm", and the three things you
/// can do with it — Download (to the phone's Downloads), Preview (open in another app)
/// and Share. Tapping the card body opens the details sheet.
class FileCard extends ConsumerWidget {
  const FileCard({super.key, required this.file, this.snippet = '', this.flat = false});

  final DocFile file;
  final String snippet;

  /// Outline only, for a card that already sits inside another card (a chat bubble).
  final bool flat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final client = ref.watch(clientDirectoryProvider)[file.clientId]?.display;
    final dl = ref.watch(downloadControllerProvider
        .select((m) => m[file.key] ?? const DownloadState()));
    final busy = ref.watch(fileOpenControllerProvider.select((m) => m[file.key]));
    final kind = FileKind.of(file.fileName);

    Future<void> run(Future<String?> Function() op) async {
      final err = await op();
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }

    final open = ref.read(fileOpenControllerProvider.notifier);
    final downloading = dl.phase == DownloadPhase.running;
    final pct = downloading && dl.progress >= 0 ? ' ${(dl.progress * 100).round()}%' : '';

    return Container(
      decoration: Ds.card(flat: flat, radius: flat ? Ds.rChip + 2 : Ds.rCard),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Ds.rCard),
          onTap: () => showFileActions(context, file: file, snippet: snippet),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s4, Ds.s4, Ds.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Badge(kind: kind),
                    const SizedBox(width: Ds.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file.fileName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(client ?? 'Client #${file.clientId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                if (downloading) ...[
                  const SizedBox(height: Ds.s3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: dl.progress >= 0 ? dl.progress : null,
                      minHeight: 4,
                    ),
                  ),
                ],
                const SizedBox(height: Ds.s3),
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        onPressed: downloading
                            ? null
                            : () => ref.read(downloadControllerProvider.notifier).start(file),
                        icon: Icon(
                            dl.phase == DownloadPhase.complete
                                ? Icons.download_done
                                : Icons.download_rounded,
                            size: 18),
                        label: Text(downloading
                            ? 'Downloading$pct'
                            : dl.phase == DownloadPhase.complete
                                ? 'Saved'
                                : 'Download'),
                      ),
                    ),
                    const SizedBox(width: Ds.s2),
                    _SideAction(
                      icon: Icons.visibility_outlined,
                      label: 'Preview',
                      busy: busy == FileOp.preview,
                      onTap: busy != null ? null : () => run(() => open.preview(file)),
                    ),
                    const SizedBox(width: Ds.s2),
                    _SideAction(
                      icon: Icons.ios_share_rounded,
                      label: 'Share',
                      busy: busy == FileOp.share,
                      onTap: busy != null ? null : () => run(() => open.share(file)),
                    ),
                  ],
                ),
                if (dl.phase == DownloadPhase.error && dl.error != null) ...[
                  const SizedBox(height: Ds.s2),
                  Text(dl.error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: Ds.red)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 4,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 16),
            const SizedBox(width: 4),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// Coarse document type, from the extension — enough for a coloured badge.
class FileKind {
  const FileKind(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  static FileKind of(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'pdf':
        return const FileKind('PDF', Icons.picture_as_pdf_outlined, Ds.red);
      case 'xls':
      case 'xlsx':
      case 'csv':
        return const FileKind('XLS', Icons.table_chart_outlined, Ds.green);
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return const FileKind('DOC', Icons.article_outlined, Ds.blue);
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return const FileKind('IMG', Icons.image_outlined, Ds.violet);
      case 'zip':
      case 'rar':
      case '7z':
        return const FileKind('ZIP', Icons.folder_zip_outlined, Ds.amber);
      default:
        return FileKind(ext.isEmpty ? 'FILE' : ext.toUpperCase(),
            Icons.insert_drive_file_outlined, Ds.muted);
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.kind});
  final FileKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Ds.rChip),
      ),
      child: Icon(kind.icon, color: kind.color, size: 24),
    );
  }
}
