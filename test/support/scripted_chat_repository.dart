// A ChatRepository that replays a scripted list of SSE payloads.
//
// `chatRepositoryProvider` is overridable, which is the seam that lets a test drive
// the REAL ChatController — the pairing logic under test lives there, not in a
// widget, so there is no point testing a reimplementation of it.

import 'package:dio/dio.dart';
import 'package:docsync_app/features/chat/model/chat_models.dart';
import 'package:docsync_app/features/chat/model/chat_repository.dart';

class ScriptedChatRepository implements ChatRepository {
  ScriptedChatRepository(this.script, {this.messages = const []});

  /// Raw decoded `data:` payloads, in the order the server would send them.
  final List<Map<String, dynamic>> script;

  /// What [conversationMessages] returns.
  final List<ChatMessage> messages;

  /// The queries [answerStream] was asked for, in order.
  final List<String> asked = [];

  /// The (voice, lang) each [answerStream] call was made with, in order.
  final List<({bool voice, String? lang})> voiceFlags = [];

  @override
  Stream<RagEvent> answerStream(
    String query, {
    int conv = 0,
    int k = 10,
    bool voice = false,
    String? lang,
    CancelToken? cancel,
  }) async* {
    asked.add(query);
    voiceFlags.add((voice: voice, lang: lang));
    for (final j in script) {
      final ev = RagEvent.fromJson(j);
      yield ev;
      if (ev.type == RagEventType.finalAnswer ||
          ev.type == RagEventType.error ||
          ev.type == RagEventType.unavailable) {
        break; // same termination rule as the real repository
      }
    }
  }

  /// Conversations [markSeen] was told had been read, in order.
  final List<int> seen = [];

  @override
  Future<void> markSeen(int conv) async {
    if (conv > 0) seen.add(conv);
  }

  /// Conversations [followStream] was asked to follow, in order.
  final List<int> followed = [];

  /// When false, following yields nothing — the server saying "no turn is running".
  bool hasLiveTurn = true;

  /* A resumed turn replays the SAME events as a live one, which is the property worth testing:
     if the fold behaves differently on the two paths, a followed turn renders differently from
     the one that produced it, and nobody would see that until two devices disagreed. */
  /// Conversations [stop] was called for, in order.
  final List<int> stopped = [];

  @override
  Future<bool> stop(int conv) async {
    if (conv <= 0) return false;
    stopped.add(conv);
    return true;
  }

  @override
  Stream<RagEvent> followStream(int conv, {int after = 0, CancelToken? cancel}) async* {
    followed.add(conv);
    if (!hasLiveTurn) return;
    for (final j in script) {
      final ev = RagEvent.fromJson(j);
      yield ev;
      if (ev.type == RagEventType.finalAnswer ||
          ev.type == RagEventType.error ||
          ev.type == RagEventType.unavailable) {
        break;
      }
    }
  }

  /// Every commit this repository was asked to make.
  final List<({String action, Map<String, dynamic> args, int conv})> commits =
      [];

  /// What [commit] answers. Mutable so a test can fail once and then succeed.
  CommitResult commitResult = const CommitResult(true, 'Done.');

  @override
  Future<CommitResult> commit(String action, Map<String, dynamic> args,
      {int conv = 0}) async {
    commits.add((action: action, args: args, conv: conv));
    return commitResult;
  }

  @override
  Future<List<Conversation>> listConversations() async => const [];

  @override
  Future<List<ChatMessage>> conversationMessages(int id) async => messages;
}
