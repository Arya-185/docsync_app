import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/chat_controller.dart';
import '../../controller/commit_ledger.dart';
import '../../model/chat_models.dart';

/// A `[high_write]` proposal: the server proposes, the user confirms here, and
/// ai_commit.php performs the write on this session.
///
/// This replaces "(Confirm this in the desktop app.)", which blocked all eight
/// confirmable actions on mobile. It is also the fallback whenever the A2UI
/// confirm surface did not render, which is why the buttons and the POST live here
/// rather than inside the renderer glue.
///
/// On failure the buttons come BACK. A write that could not be made must leave the
/// user something to press.
class ConfirmCard extends ConsumerStatefulWidget {
  const ConfirmCard({super.key, required this.proposal});

  final ConfirmProposal proposal;

  @override
  ConsumerState<ConfirmCard> createState() => _ConfirmCardState();
}

enum _Phase { idle, working, committed, cancelled }

class _ConfirmCardState extends ConsumerState<ConfirmCard> {
  _Phase _phase = _Phase.idle;
  String _note = '';
  bool _noteIsError = false;

  int get _conv => ref.read(chatControllerProvider).conversationId;

  Future<void> _confirm() async {
    setState(() {
      _phase = _Phase.working;
      _note = 'Working…';
      _noteIsError = false;
    });
    // Through the ledger: the same proposal may also be answered by voice.
    final res = await ref
        .read(commitLedgerProvider.notifier)
        .commit(_conv, widget.proposal.name, widget.proposal.commitArgs,
            proposalKey: widget.proposal.key);
    if (!mounted) return;
    setState(() {
      _phase = res.ok ? _Phase.committed : _Phase.idle;
      _note = res.message;
      _noteIsError = !res.ok;
    });
  }

  void _cancel() {
    ref
        .read(commitLedgerProvider.notifier)
        .cancel(_conv, widget.proposal.name, widget.proposal.commitArgs);
    setState(() {
      _phase = _Phase.cancelled;
      _note = 'Cancelled.';
      _noteIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = widget.proposal;
    // Answered elsewhere (by voice)? Retire the buttons here too.
    final conv = ref.watch(chatControllerProvider.select((s) => s.conversationId));
    final key = CommitLedger.keyFor(conv, p.name, p.commitArgs);
    final other = ref.watch(commitLedgerProvider.select((l) => l[key]));
    if (_phase == _Phase.idle && other != null) {
      switch (other.phase) {
        case CommitPhase.working:
          _phase = _Phase.working;
          _note = 'Working…';
        case CommitPhase.done:
          _phase = _Phase.committed;
          _note = other.message;
        case CommitPhase.cancelled:
          _phase = _Phase.cancelled;
          _note = 'Cancelled.';
      }
    } else if (_phase == _Phase.working && other?.phase == CommitPhase.done) {
      _phase = _Phase.committed;
      _note = other!.message;
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text('Please confirm',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(p.summary.isNotEmpty ? p.summary : 'Confirm this action?'),
          for (final w in p.warnings) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: scheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(w,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ],
          if (_phase == _Phase.idle || _phase == _Phase.working) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: _phase == _Phase.working ? null : _confirm,
                  child: const Text('Confirm'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _phase == _Phase.working ? null : _cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _noteIsError
                    ? scheme.error
                    : _phase == _Phase.committed
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
