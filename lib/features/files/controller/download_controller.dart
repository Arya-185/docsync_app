import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/models/doc_file.dart';
import '../model/download_repository.dart';

final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => DownloadRepository(ref.watch(apiClientProvider)),
);

enum DownloadPhase { idle, running, complete, error }

class DownloadState {
  final DownloadPhase phase;
  final double progress; // 0..1, or -1 when total size is unknown
  final String? savedPath;
  final String? error;

  const DownloadState({
    this.phase = DownloadPhase.idle,
    this.progress = 0,
    this.savedPath,
    this.error,
  });
}

/// Tracks download state for every file the user has interacted with, keyed by
/// [DocFile.key]. A view reads the state for its own file via [stateFor].
final downloadControllerProvider =
    NotifierProvider<DownloadController, Map<String, DownloadState>>(
        DownloadController.new);

class DownloadController extends Notifier<Map<String, DownloadState>> {
  @override
  Map<String, DownloadState> build() => const {};

  DownloadState stateFor(DocFile file) =>
      state[file.key] ?? const DownloadState();

  void _set(String key, DownloadState s) => state = {...state, key: s};

  /// Start (or restart) a download. Safe to call again after a previous
  /// download of the same file completed or failed — it downloads afresh.
  Future<void> start(DocFile file) async {
    final key = file.key;
    if (stateFor(file).phase == DownloadPhase.running) return; // already going
    _set(key, const DownloadState(phase: DownloadPhase.running, progress: -1));
    try {
      final path = await ref.read(downloadRepositoryProvider).download(
            file,
            onProgress: (p) => _set(
              key,
              DownloadState(phase: DownloadPhase.running, progress: p),
            ),
          );
      _set(key, DownloadState(phase: DownloadPhase.complete, progress: 1, savedPath: path));
    } catch (e) {
      _set(key, DownloadState(phase: DownloadPhase.error, error: e.toString()));
    }
  }
}
