import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/models/doc_file.dart';
import 'download_controller.dart';

/// What a file card is busy doing right now, per [DocFile.key]. Download progress is
/// tracked separately by [downloadControllerProvider]; this covers Preview and Share,
/// which fetch into the app cache first.
enum FileOp { preview, share }

final fileOpenControllerProvider =
    NotifierProvider<FileOpenController, Map<String, FileOp>>(FileOpenController.new);

class FileOpenController extends Notifier<Map<String, FileOp>> {
  @override
  Map<String, FileOp> build() => const {};

  FileOp? busy(DocFile file) => state[file.key];

  /// Open [file] in whatever app on the phone handles its type. Returns an error to show,
  /// or null on success.
  Future<String?> preview(DocFile file) => _run(file, FileOp.preview, (path) async {
        final r = await OpenFilex.open(path);
        switch (r.type) {
          case ResultType.done:
            return null;
          case ResultType.noAppToOpen:
            return 'No app on this phone can open ${file.fileName}.';
          default:
            return r.message.isEmpty ? 'Could not open the file.' : r.message;
        }
      });

  /// Hand [file] to the Android share sheet.
  Future<String?> share(DocFile file) => _run(file, FileOp.share, (path) async {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(path)],
          subject: file.fileName,
        ));
        return null;
      });

  Future<String?> _run(
    DocFile file,
    FileOp op,
    Future<String?> Function(String path) use,
  ) async {
    if (state.containsKey(file.key)) return null; // one action per file at a time
    state = {...state, file.key: op};
    try {
      final f = await ref.read(downloadRepositoryProvider).fetchToCache(file);
      return await use(f.path);
    } catch (e) {
      return e.toString();
    } finally {
      if (ref.mounted) state = {...state}..remove(file.key);
    }
  }
}
