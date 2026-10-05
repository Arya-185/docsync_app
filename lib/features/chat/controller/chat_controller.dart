import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import '../../../shared/models/citation.dart';
import '../../clients/controller/client_directory.dart';
import '../model/ai_credits.dart';
import '../model/chat_models.dart';
import '../model/chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

/// Saved conversations for the history panel (most recent first).
final chatHistoryProvider = FutureProvider.autoDispose<List<Conversation>>(
  (ref) => ref.watch(chatRepositoryProvider).listConversations(),
);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  /// Cancels the HTTP stream of the turn on screen. Only used to abandon it locally (sign-out):
  /// the turn itself lives on the server and carries on — Stop is [stop], not this.
  CancelToken? _cancel;

  /// Stop was pressed before the server said which conversation this is (a brand-new chat's
  /// first seconds). Sent the moment the `conversation` event arrives.
  bool _stopRequested = false;

  void newChat() => state = const ChatState();

  /// Ask the server to stop the running turn. The stream keeps going until the agent reaches its
  /// next check and ends with `final.stopped`, so [ChatState.stopping] covers that gap.
  Future<void> stop() async {
    if (!state.sending || state.stopping) return;
    state = state.copyWith(stopping: true);
    final id = state.conversationId;
    if (id > 0) {
      await _repo.stop(id);
    } else {
      _stopRequested = true;
    }
  }

  /// Drop the turn on screen without stopping it server-side — for sign-out, where the next
  /// account must not receive this one's events.
  void cancelActive() => _cancel?.cancel('abandoned');

  /// Catch up after the app was in the background: an answer may have landed, or still be
  /// running, while nothing was listening. Unlike [openConversation] this keeps the transcript on
  /// screen instead of blanking it first.
  Future<void> resync() async {
    final id = state.conversationId;
    if (id <= 0 || state.sending) return;
    final msgs = await _repo.conversationMessages(id);
    if (!ref.mounted || state.sending || state.conversationId != id) return;
    if (msgs.isNotEmpty && msgs.length >= state.messages.length) {
      state = state.copyWith(messages: msgs);
    }
    unawaited(follow(id));
  }

  /// Load a saved conversation's messages into the chat view.
  Future<void> openConversation(int id) async {
    state = const ChatState(status: ChatStatus.sending); // brief loading gate
    final msgs = await _repo.conversationMessages(id);
    state = ChatState(messages: msgs, conversationId: id);
    final ids = msgs.expand((m) => m.citations).map((c) => c.clientId).toSet();
    if (ids.isNotEmpty) {
      ref.read(clientDirectoryProvider.notifier).ensure(ids);
    }
    /* The transcript we just loaded may be missing its last answer because that answer is still
       being written — on the web, or on this phone before it was closed. Always ask: the server
       answers immediately when nothing is running, so this costs one short request and removes
       the case where a question sits looking permanently unanswered. Not awaited, so opening a
       chat is never held up by it. */
    unawaited(_repo.markSeen(id));
    unawaited(follow(id));
  }

  /// Ask a question. Returns false when it was NOT sent — empty, or another answer is still
  /// running — so the caller can say so instead of the tap silently doing nothing.
  ///
  /// [voice] asks for a reply meant to be spoken; [lang] is the language the user spoke.
  Future<bool> send(String query, {bool voice = false, String? lang}) async {
    final q = query.trim();
    if (q.isEmpty || state.sending) return false;
    await _runTurn(
      open: (cancel) => _repo.answerStream(q,
          conv: state.conversationId, voice: voice, lang: lang, cancel: cancel),
      question: q,
      openingLabel: 'Sending your question',
      openedLabel: 'Sent your question',
    );
    return true;
  }

  /// Attach to a turn that is already running on this conversation.
  ///
  /// A turn belongs to the conversation, not to the client that started it: it keeps running
  /// after the app is backgrounded or killed, and it may have been started on the web. Opening
  /// such a chat picks it up rather than showing a question with nothing under it.
  ///
  /// The events are the SAME events a live turn sends, so this runs the identical fold — which
  /// is the whole reason following costs no new rendering code. Returns without touching the
  /// state when nothing is running, so it is safe to call on every open.
  Future<void> follow(int conv) async {
    if (conv <= 0 || state.sending) return;
    await _runTurn(
      open: (cancel) => _repo.followStream(conv, cancel: cancel),
      question: null,
      openingLabel: 'Picking up where this answer got to',
      openedLabel: 'Picked up this answer',
    );
  }

  /// The one fold for both a turn we started and a turn we joined.
  ///
  /// [question] is null when joining: there is no user message to append, because the question
  /// is already in the transcript we just loaded.
  Future<void> _runTurn({
    required Stream<RagEvent> Function(CancelToken cancel) open,
    required String? question,
    required String openingLabel,
    required String openedLabel,
  }) async {
    final cancel = CancelToken();
    _cancel = cancel;
    _stopRequested = false;
    final msgs = [
      ...state.messages,
      if (question != null) ChatMessage(role: 'user', content: question),
      const ChatMessage(role: 'assistant', streaming: true),
    ];
    /* The trail opens BEFORE the server has said anything: the request itself can
       take a moment, and an empty bubble is the thing it exists to get rid of. */
    final trail = <ChatStep>[
      ChatStep(seq: ChatStep.sentSeq, label: openingLabel, startedAt: DateTime.now()),
    ];
    var trailDone = false;
    var started = false;

    /* Claim the bubble and show the trail.

       A turn we START does this immediately: the request itself takes a moment and an empty
       bubble is the thing the trail exists to get rid of. A turn we FOLLOW must not, because
       the common case by far is that nothing is running -- the chat is simply being opened --
       and eagerly adding a placeholder left an empty assistant bubble under every conversation
       the user looked at. So following waits for the first real event before touching anything,
       and if none arrives this method is a no-op the user never sees. */
    void begin() {
      if (started || !ref.mounted) return;
      started = true;
      state = ChatState(
        messages: msgs,
        conversationId: state.conversationId,
        status: ChatStatus.sending,
        trail: List.of(trail),
      );
    }

    if (question != null) begin();

    var answer = '';
    var thinking = '';
    var sawAnswerText = false; // a confirm-only turn legitimately has none
    final surfaces = <Map<String, dynamic>>[];
    final superseded = <String>[];
    final proposals = <ConfirmProposal>[];
    List<Citation> citations = const [];

    /* Every write below is guarded by ref.mounted: signing out invalidates this provider while a
       turn may still be streaming, and a disposed notifier must not be written to. */
    void pushTrail({bool? done, double? elapsed}) {
      if (!ref.mounted) return;
      state = state.copyWith(
        trail: List.of(trail),
        trailDone: done,
        elapsed: elapsed,
      );
    }

    /// Close the open line with [seq]. False when no such line is open — which is
    /// how a legacy completion-only `step` is told apart from a paired one.
    bool closeStep(int? seq, String? label, bool failed) {
      if (seq == null) return false;
      final i = trail.indexWhere((s) => s.seq == seq);
      if (i < 0) return false;
      trail[i] = trail[i].copyWith(
        done: true,
        failed: failed,
        label: (label ?? '').isNotEmpty ? label : null,
      );
      return true;
    }

    /// Nothing is still running once the stream is over, however it ended — and a
    /// confirm turn, an error and an `unavailable` all end WITHOUT a `final`.
    void finishTrail({double elapsed = 0}) {
      if (trailDone) return;
      for (var i = 0; i < trail.length; i++) {
        trail[i] = trail[i].copyWith(done: true);
      }
      trail.removeWhere((s) => s.transient);
      trailDone = true;
      pushTrail(done: true, elapsed: elapsed);
    }

    void updateAssistant({
      String? content,
      List<Citation>? cites,
      bool? streaming,
      String? think,
      List<Map<String, dynamic>>? a2ui,
      ConfirmProposal? confirm,
      List<ConfirmProposal>? confirms,
      List<String>? superseded,
    }) {
      if (!ref.mounted) return;
      final list = [...state.messages];
      final idx = list.length - 1;
      list[idx] = list[idx].copyWith(
        content: content,
        citations: cites,
        streaming: streaming,
        thinking: think,
        a2ui: a2ui,
        confirm: confirm,
        confirms: confirms,
        supersedes: superseded,
      );
      state = state.copyWith(messages: list);
    }

    try {
      await for (final ev in open(cancel)) {
        if (!ref.mounted) break;
        begin();
        switch (ev.type) {
          case RagEventType.conversation:
            state = state.copyWith(conversationId: ev.conversationId ?? state.conversationId);
            if (_stopRequested && state.conversationId > 0) {
              _stopRequested = false;
              unawaited(_repo.stop(state.conversationId));
            }
            break;
          case RagEventType.token:
            answer += ev.text ?? '';
            sawAnswerText = true;
            updateAssistant(content: answer);
            break;
          case RagEventType.thinking:
            thinking += ev.text ?? '';
            updateAssistant(think: thinking);
            break;
          case RagEventType.stepStart:
            closeStep(ChatStep.sentSeq, openedLabel, false);
            /* A transient line earns its place only while it is running. The
               repeated "Planning the next step" rounds are real waits worth
               showing live, but as history they bury the lines that say what
               was actually done. */
            trail.removeWhere((s) => s.transient && s.done);
            trail.add(ChatStep(
              seq: ev.seq,
              label: (ev.label ?? '').isNotEmpty ? ev.label! : 'Working',
              transient: ev.transient,
              startedAt: DateTime.now(),
            ));
            pushTrail();
            break;
          case RagEventType.step:
            if (!closeStep(ev.seq, ev.doneLabel, ev.failed)) {
              // No open line: a legacy completion-only event. Append it already
              // finished — but draw nothing at all for a tool we do not know.
              final label = (ev.doneLabel ?? '').isNotEmpty
                  ? ev.doneLabel
                  : ev.legacyLabel;
              if (label != null && label.isNotEmpty) {
                trail.add(ChatStep(
                  seq: ev.seq,
                  label: label,
                  done: true,
                  failed: ev.failed,
                ));
              }
            }
            pushTrail();
            break;
          case RagEventType.a2ui:
            if (ev.a2uiMessage != null) {
              surfaces.add(ev.a2uiMessage!);
              /* The block of prose these cards stand in for is recorded, not applied. Whether
                 the text may actually be dropped depends on the surface having rendered,
                 which only the widget can know — see ChatMessage.visibleContent. */
              if (ev.supersedes != null && !superseded.contains(ev.supersedes)) {
                superseded.add(ev.supersedes!);
              }
              updateAssistant(
                a2ui: List.of(surfaces),
                superseded: List.of(superseded),
              );
            }
            break;
          case RagEventType.finalAnswer:
            if ((ev.answer ?? '').isNotEmpty) {
              answer = ev.answer!;
              sawAnswerText = true;
            } else if (ev.stopped && answer.isEmpty) {
              answer = 'Stopped.';
              sawAnswerText = true;
            }
            citations = _consolidateCitations(ev.citations);
            updateAssistant(content: answer, cites: citations);
            finishTrail(elapsed: ev.elapsed);
            break;
          case RagEventType.confirm:
            /* No longer "confirm this in the desktop app". The proposal is kept on
               the message; the bubble renders the A2UI surface when one arrived and
               this card otherwise, and either one POSTs to ai_commit.php. */
            /* A multi-part reply (server M5) sends one `confirm` per card. Keep them ALL, the
               first staying `confirm` for everything that reads one: assigning each new one
               over the last left the earlier card with no fallback and nothing for voice. */
            if (ev.proposal != null) {
              proposals.add(ev.proposal!);
              updateAssistant(confirm: proposals.first, confirms: List.of(proposals));
            }
            break;
          case RagEventType.unavailable:
            answer = _unavailableMessage(ev.reason);
            sawAnswerText = true;
            updateAssistant(content: answer);
            break;
          case RagEventType.error:
            answer = _errorMessage(ev.message);
            sawAnswerText = true;
            updateAssistant(content: answer);
            break;
          case RagEventType.ignore:
            // the `credits` event updates the header counter; usage/ping are just skipped
            if (ev.credits != null) ref.read(aiCreditsProvider.notifier).set(ev.credits);
            break; // benign event (usage/ping) — keep streaming
        }
      }
    } catch (e) {
      // Abandoned on purpose (sign-out): the turn carries on server-side; say nothing here.
      final abandoned = e is DioException && CancelToken.isCancel(e);
      if (answer.isEmpty && !abandoned) {
        answer = 'Something went wrong: $e';
        sawAnswerText = true;
        updateAssistant(content: answer);
      }
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      /* Guarded rather than returned out of: a `return` in a finally swallows whatever
         exception was on its way out. `started` is false only when a FOLLOWED turn found
         nothing running, in which case the transcript is left exactly as it was found. */
      if (started && ref.mounted) {
        /* "(no answer)" used to run unconditionally, so a confirm-only turn — which
           legitimately produces no prose at all — printed those literal words under
           the confirmation card. Only say it when the turn really said nothing AND
           left nothing to interact with. */
        final hasWidget =
            surfaces.isNotEmpty || state.messages.last.confirm != null;
        final text = sawAnswerText || answer.isNotEmpty
            ? answer
            : (hasWidget ? '' : 'No answer.');
        updateAssistant(
          content: text,
          cites: citations,
          streaming: false,
        );
        finishTrail();
        state = state.copyWith(status: ChatStatus.idle, step: '', stopping: false);

        // Resolve client names for any citation chips.
        if (citations.isNotEmpty) {
          ref.read(clientDirectoryProvider.notifier)
              .ensure(citations.map((c) => c.clientId).toSet());
        }

        /* The answer is on screen, so this chat is read — marked before the history is
           refreshed, or the list would come back still showing its dot. */
        unawaited(_repo.markSeen(state.conversationId));

        // Refresh the history panel (this turn created/updated a conversation).
        ref.invalidate(chatHistoryProvider);
      }
    }
  }

  /// Consolidate repeated citations of the same file (first occurrence wins,
  /// preserving the model's ordering) and cap to the top 5.
  List<Citation> _consolidateCitations(List<Citation> cites) {
    final seen = <String>{};
    final out = <Citation>[];
    for (final c in cites) {
      if (seen.add(c.key)) out.add(c);
      if (out.length >= AppConfig.maxResults) break;
    }
    return out;
  }

  String _unavailableMessage(String? reason) {
    switch (reason) {
      case 'offline':
        return 'The main PC is offline right now. Please try again shortly.';
      case 'disabled':
        return 'AI search isn\'t enabled for this company.';
      case 'busy':
        return 'The AI service is busy. Please try again in a moment.';
      default:
        return 'The AI service is unavailable right now.';
    }
  }

  String _errorMessage(String? message) {
    if (message == 'not_authenticated') {
      return 'Your session expired. Please sign out and back in.';
    }
    if (message == 'empty_query') return 'Please enter a question.';
    return 'Error: ${message ?? 'unknown'}';
  }
}
