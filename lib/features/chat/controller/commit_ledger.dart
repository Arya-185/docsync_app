import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/chat_models.dart';
import 'chat_controller.dart';

enum CommitPhase { working, done, cancelled }

class CommitEntry {
  const CommitEntry(this.phase, [this.message = '']);
  final CommitPhase phase;
  final String message;
}

/// Every confirmed (or cancelled) write this session, keyed by WHAT it writes.
///
/// A proposal can now be answered three ways — the legacy Confirm card, the A2UI confirm
/// surface, and a spoken "yes" — and each used to keep its own "already done" flag. That was
/// fine while there was one way; with three, saying yes and then tapping Confirm (or tapping
/// Cancel and then saying yes) would each have been honoured. One ledger, keyed by the
/// conversation plus the action plus its exact arguments, means one write per proposal no
/// matter who answers it.
final commitLedgerProvider =
    NotifierProvider<CommitLedger, Map<String, CommitEntry>>(CommitLedger.new);

class CommitLedger extends Notifier<Map<String, CommitEntry>> {
  @override
  Map<String, CommitEntry> build() => const {};

  static String keyFor(int conv, String action, Map<String, dynamic> args) {
    final sorted = Map.fromEntries(args.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    return '$conv|$action|${jsonEncode(sorted)}';
  }

  CommitEntry? entry(int conv, String action, Map<String, dynamic> args) =>
      state[keyFor(conv, action, args)];

  /// Commit once. A second call while one is in flight, after it succeeded, or after the user
  /// cancelled, writes nothing and says why. A FAILED commit is forgotten, so it can be retried.
  ///
  /// [proposalKey] is the card's key when one reply carried several (server M5), passed through
  /// to ai_commit.php. The ledger itself stays keyed by what is WRITTEN: two cards in one reply
  /// differ in their arguments.
  Future<CommitResult> commit(int conv, String action, Map<String, dynamic> args,
      {String proposalKey = ''}) async {
    final key = keyFor(conv, action, args);
    switch (state[key]?.phase) {
      case CommitPhase.working:
        return const CommitResult(false, 'Already working on it…');
      case CommitPhase.done:
        return CommitResult(false, state[key]!.message.isEmpty ? 'Already done.' : state[key]!.message);
      case CommitPhase.cancelled:
        return const CommitResult(false, 'That was cancelled.');
      case null:
        break;
    }
    state = {...state, key: const CommitEntry(CommitPhase.working)};
    CommitResult res;
    try {
      res = await ref
          .read(chatRepositoryProvider)
          .commit(action, args, conv: conv, key: proposalKey);
    } catch (e) {
      res = CommitResult(false, 'Could not confirm: $e');
    }
    if (!ref.mounted) return res;
    if (res.ok) {
      state = {...state, key: CommitEntry(CommitPhase.done, res.message)};
    } else {
      state = {...state}..remove(key);
    }
    return res;
  }

  /// The user declined. Recorded so a later "yes" (or tap) cannot resurrect it.
  void cancel(int conv, String action, Map<String, dynamic> args) {
    final key = keyFor(conv, action, args);
    if (state[key]?.phase == CommitPhase.working || state[key]?.phase == CommitPhase.done) return;
    state = {...state, key: const CommitEntry(CommitPhase.cancelled)};
  }
}
