import '../../../shared/models/citation.dart';
import '../../../shared/models/util.dart';

/// A chat message in a conversation.
class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final List<Citation> citations;
  final bool streaming;

  /// The reasoning model's live chain-of-thought for this turn. Display-only and
  /// ephemeral — streamed during the answer, never persisted, so history loads empty.
  final String thinking;

  /// The raw A2UI protocol messages the server composed for THIS turn, in arrival
  /// order. Held as decoded JSON, not as a renderer object: a [ChatMessage] is
  /// immutable value state and a surface controller is a mutable disposable that
  /// belongs to the widget. The bubble replays these into its own controller.
  final List<Map<String, dynamic>> a2ui;

  /// A legacy `confirm` proposal for this turn, or null. The server emits BOTH this
  /// and the equivalent A2UI surface; this stays the fallback for when no surface
  /// actually rendered.
  final ConfirmProposal? confirm;

  /// Blocks of [content] that an arriving surface says it replaces.
  ///
  /// A results list is sent TWICE — as cards and as prose — because a client that cannot draw
  /// a surface must still get the rows, and the server never persists an empty answer. These
  /// are the exact substrings the cards stand in for.
  ///
  /// They are kept here as data and NOT applied to [content], because whether the text may be
  /// dropped depends on whether the surface actually rendered, which only the widget knows.
  /// Use [visibleContent]. Keeping [content] whole also means history and persistence are
  /// unaffected by a rendering decision.
  final List<String> supersedes;

  const ChatMessage({
    required this.role,
    this.content = '',
    this.citations = const [],
    this.streaming = false,
    this.thinking = '',
    this.a2ui = const [],
    this.confirm,
    this.supersedes = const [],
  });

  bool get isUser => role == 'user';

  /// [content] with the superseded blocks removed.
  ///
  /// Pass `rendered: false` — the default — and nothing is removed. That is the safe
  /// direction and the whole point: a surface that failed to draw must leave the rows behind
  /// as text, or they vanish from the conversation entirely.
  String visibleContent({bool rendered = false}) {
    if (!rendered || supersedes.isEmpty || content.isEmpty) return content;
    var out = content;
    for (final block in supersedes) {
      if (block.isEmpty) continue;
      out = out.replaceAll(block, '');
    }
    // Removing a block from the middle leaves the blank lines that surrounded it.
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  ChatMessage copyWith({
    String? content,
    List<Citation>? citations,
    bool? streaming,
    String? thinking,
    List<Map<String, dynamic>>? a2ui,
    ConfirmProposal? confirm,
    List<String>? supersedes,
  }) =>
      ChatMessage(
        role: role,
        content: content ?? this.content,
        citations: citations ?? this.citations,
        streaming: streaming ?? this.streaming,
        thinking: thinking ?? this.thinking,
        a2ui: a2ui ?? this.a2ui,
        confirm: confirm ?? this.confirm,
        supersedes: supersedes ?? this.supersedes,
      );

  /* Value equality, so a `.select` on the screen can actually skip a rebuild.
     Without it every streamed token rebuilds every bubble: the default identity
     equality never matches a freshly-copied message. The collection fields are
     compared by IDENTITY on purpose — the controller always replaces them
     wholesale rather than mutating in place, so identity is correct and O(1). */
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          other.role == role &&
          other.content == content &&
          identical(other.citations, citations) &&
          other.streaming == streaming &&
          other.thinking == thinking &&
          identical(other.a2ui, a2ui) &&
          identical(other.confirm, confirm) &&
          identical(other.supersedes, supersedes);

  @override
  int get hashCode => Object.hash(role, content, citations, streaming, thinking,
      a2ui.length, confirm, supersedes.length);

  /// Rebuild a message loaded from the server.
  ///
  /// `meta` (server migration 034) carries the turn's INTERACTIVE part: the proposal it was
  /// waiting on and the surfaces it drew. Without it, reopening a conversation showed the
  /// sentence "Proposed an action for your confirmation: ..." with no way to confirm it — a
  /// description of a decision the user could no longer make. That mattered little while a turn
  /// died with its client; now that a turn lives on the server and any device can open the chat,
  /// it is the difference between watching a proposal appear and being able to act on it.
  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final meta = j['meta'] is Map ? Map<String, dynamic>.from(j['meta'] as Map) : null;
    final proposal = meta != null && meta['confirm'] is Map
        ? ConfirmProposal.fromJson(Map<String, dynamic>.from(meta['confirm'] as Map))
        : null;
    final surfaces = meta != null && meta['a2ui'] is List
        ? (meta['a2ui'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
        : const <Map<String, dynamic>>[];
    return ChatMessage(
      role: (j['role'] ?? 'assistant').toString(),
      content: (j['content'] ?? '').toString(),
      citations: (j['citations'] as List?)
              ?.map((c) => Citation.fromJson(Map<String, dynamic>.from(c)))
              .toList() ??
          const [],
      a2ui: surfaces,
      confirm: proposal,
    );
  }
}

/// A saved conversation summary.
class Conversation {
  final int id;
  final String title;
  final String updatedAt;

  /// An answer arrived here since this chat was last opened.
  ///
  /// A turn runs to completion on the server whatever the client does, so an answer can land
  /// in a chat nobody is looking at — asked on the web and left, or asked here and the app
  /// closed. Without a mark there is nothing to tell you to go back and look.
  final bool unseen;

  const Conversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.unseen = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: asInt(j['id']),
        title: (j['title'] ?? 'Untitled').toString(),
        updatedAt: (j['updated_at'] ?? '').toString(),
        unseen: j['unseen'] == true,
      );
}

/// A `[high_write]` proposal the user must confirm before anything is written.
///
/// `commitArgs` is a JSON **object** here. The JSON-*string* encoding only exists
/// inside an A2UI action context (v0.9 `DynamicValue` has no object variant);
/// re-encoding this one would make ai_commit.php answer `bad_request`.
class ConfirmProposal {
  final String name;
  final String summary;
  final List<String> warnings;
  final Map<String, dynamic> commitArgs;

  const ConfirmProposal({
    required this.name,
    this.summary = '',
    this.warnings = const [],
    this.commitArgs = const {},
  });

  /// From a stored proposal (`meta.confirm`). The keys are the SSE contract's, so a card
  /// rebuilt from the transcript carries exactly what the live one would have sent.
  factory ConfirmProposal.fromJson(Map<String, dynamic> j) => ConfirmProposal(
        name: (j['name'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
        warnings: (j['warnings'] as List?)?.map((w) => w.toString()).toList() ?? const [],
        commitArgs: j['commit_args'] is Map
            ? Map<String, dynamic>.from(j['commit_args'] as Map)
            : const {},
      );
}

/// The outcome of an ai_commit.php POST. On failure the card stays usable so the
/// user can retry — a write that could not be made must not eat its own button.
class CommitResult {
  final bool ok;
  final String message;
  const CommitResult(this.ok, this.message);
}

/// One line of the activity trail.
///
/// [seq] pairs a `step_start` with the `step` that closes it. It is **null** for a
/// legacy completion-only event: those carry no seq at all, and coercing them to 0
/// would make every one of them close the same (wrong) trail line.
class ChatStep {
  /// Server sequence number, [sentSeq] for the synthetic opening line, or null
  /// for a legacy already-finished step.
  final int? seq;
  final String label;
  final bool done;
  final bool failed;

  /// A repeated "planning the next step" round: worth showing while it runs,
  /// noise once the turn is over. Dropped from the finished trail.
  final bool transient;

  /// When the line opened on this device, and how long it ran once closed — the "1.2s" in
  /// the checklist. Display-only timing, measured client-side, so deliberately left out of
  /// equality: two trails that say the same thing are the same trail.
  final DateTime? startedAt;
  final double? seconds;

  const ChatStep({
    this.seq,
    required this.label,
    this.done = false,
    this.failed = false,
    this.transient = false,
    this.startedAt,
    this.seconds,
  });

  /// The synthetic "Sending your question" line, opened before the server has said
  /// anything. Negative so it can never collide with a real server seq.
  static const int sentSeq = -1;

  /// Closing a timed line stamps its duration once; later copies keep it.
  ChatStep copyWith({String? label, bool? done, bool? failed}) {
    final closing = (done ?? this.done) && !this.done;
    return ChatStep(
      seq: seq,
      label: label ?? this.label,
      done: done ?? this.done,
      failed: failed ?? this.failed,
      transient: transient,
      startedAt: startedAt,
      seconds: seconds ??
          (closing && startedAt != null
              ? DateTime.now().difference(startedAt!).inMilliseconds / 1000
              : null),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatStep &&
          other.seq == seq &&
          other.label == label &&
          other.done == done &&
          other.failed == failed &&
          other.transient == transient;

  @override
  int get hashCode => Object.hash(seq, label, done, failed, transient);
}

/// A parsed SSE event from rag_answer.php.
enum RagEventType {
  conversation,
  token,
  thinking, // the reasoning model's live chain-of-thought (display-only)
  stepStart, // a step is BEGINNING; closed later by the `step` with the same seq
  step,
  a2ui, // one A2UI v0.9 protocol message composed server-side
  finalAnswer,
  confirm,
  unavailable,
  error,
  ignore, // unknown/benign events (e.g. "usage" token instrumentation)
}

class RagEvent {
  final RagEventType type;
  final int? conversationId;
  final String? text;
  final String? stepTool;
  final String? answer;
  final List<Citation> citations;
  final String? confirmName;
  final String? confirmSummary;
  final String? reason;
  final String? message;

  /// Pairing key for `step_start` / `step`. Null for legacy completion-only steps.
  final int? seq;

  /// `step_start`: the live label. `step`: see [doneLabel].
  final String? label;

  /// `step`: the text that replaces the running label once the step closes.
  final String? doneLabel;

  /// `step_start`: 'decide' | 'tool' | 'search' | 'answer'.
  final String? kind;

  /// `step_start`: this line is dropped from the finished history.
  final bool transient;

  /// `step`: it was skipped, errored, or came back `result.ok == false`.
  final bool failed;

  /// `final`: seconds the whole turn took, for the collapsed summary.
  final double elapsed;

  /// `a2ui`: the raw protocol message, passed through untouched.
  final Map<String, dynamic>? a2uiMessage;

  /// `a2ui`: the block of answer text this surface stands in for, when it stands in for one.
  /// Only the FIRST message of a surface carries it. See [ChatMessage.supersedes].
  final String? supersedes;

  /// `confirm`: the full proposal.
  final ConfirmProposal? proposal;

  /// `final`: the turn ended because the user pressed Stop (`rag_stop.php`).
  final bool stopped;

  const RagEvent(
    this.type, {
    this.conversationId,
    this.text,
    this.stepTool,
    this.answer,
    this.citations = const [],
    this.confirmName,
    this.confirmSummary,
    this.reason,
    this.message,
    this.seq,
    this.label,
    this.doneLabel,
    this.kind,
    this.transient = false,
    this.failed = false,
    this.elapsed = 0,
    this.a2uiMessage,
    this.supersedes,
    this.proposal,
    this.stopped = false,
  });

  factory RagEvent.fromJson(Map<String, dynamic> j) {
    final t = (j['type'] ?? '').toString();
    switch (t) {
      case 'conversation':
        return RagEvent(RagEventType.conversation, conversationId: asInt(j['id']));
      case 'token':
        return RagEvent(RagEventType.token, text: (j['text'] ?? '').toString());
      case 'thinking':
        return RagEvent(RagEventType.thinking, text: (j['text'] ?? '').toString());
      case 'step_start':
        return RagEvent(
          RagEventType.stepStart,
          seq: _seq(j),
          kind: (j['kind'] ?? '').toString(),
          stepTool: (j['name'] ?? '').toString(),
          label: (j['label'] ?? '').toString(),
          transient: j['transient'] == true,
        );
      case 'step':
        /* Not-ok, skipped or errored is a PROBLEM, not a tick: "it tried and could
           not" is information, and hiding it makes a half-finished turn look done. */
        final result = j['result'];
        final bad = j['error'] != null ||
            j['skipped'] != null ||
            (result is Map && result['ok'] == false);
        return RagEvent(
          RagEventType.step,
          stepTool: (j['tool'] ?? '').toString(),
          seq: _seq(j),
          doneLabel: j['done_label']?.toString(),
          failed: bad,
          // legacyStepLabel() needs these; they only appear on the older events.
          text: j['where']?.toString(),
          label: j['node']?.toString(),
          answer: j['query']?.toString(),
          message: j['message']?.toString(),
        );
      case 'a2ui':
        final msg = j['msg'];
        final sup = j['supersedes'];
        return RagEvent(
          RagEventType.a2ui,
          a2uiMessage: msg is Map ? Map<String, dynamic>.from(msg) : null,
          supersedes: sup is String && sup.isNotEmpty ? sup : null,
        );
      case 'final':
        return RagEvent(
          RagEventType.finalAnswer,
          answer: (j['answer'] ?? '').toString(),
          elapsed: _num(j['elapsed']),
          stopped: j['stopped'] == true,
          citations: (j['citations'] as List?)
                  ?.map((c) => Citation.fromJson(Map<String, dynamic>.from(c)))
                  .toList() ??
              const [],
        );
      case 'confirm':
        final args = j['commit_args'];
        return RagEvent(
          RagEventType.confirm,
          confirmName: (j['name'] ?? '').toString(),
          confirmSummary: (j['summary'] ?? '').toString(),
          proposal: ConfirmProposal(
            name: (j['name'] ?? '').toString(),
            summary: (j['summary'] ?? '').toString(),
            warnings: (j['warnings'] as List?)
                    ?.map((w) => w.toString())
                    .where((w) => w.trim().isNotEmpty)
                    .toList() ??
                const [],
            // an OBJECT here, deliberately — see [ConfirmProposal.commitArgs].
            commitArgs: args is Map ? Map<String, dynamic>.from(args) : const {},
          ),
        );
      case 'unavailable':
        return RagEvent(RagEventType.unavailable, reason: (j['reason'] ?? '').toString());
      case 'error':
        return RagEvent(RagEventType.error, message: (j['message'] ?? t).toString());
      default:
        // Unknown/benign events (e.g. "usage", "ping") — ignore, don't abort.
        return RagEvent(RagEventType.ignore, message: t);
    }
  }

  /* A legacy completion-only step has NO `seq` key at all, and must keep a null
     one: run through asInt() they would all become 0 and close each other's
     lines. Absence is the signal, so test for the key, not for the value. */
  static int? _seq(Map<String, dynamic> j) =>
      j.containsKey('seq') && j['seq'] != null ? asInt(j['seq']) : null;

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  /// A legacy (completion-only) step folded into a trail line, or null to draw
  /// nothing. Mirrors `legacyStepLabel` in app/ask_ai.php — an unknown tool must
  /// produce NO line rather than a blank one.
  String? get legacyLabel {
    switch (stepTool) {
      case 'queued':
        return (message ?? '').isNotEmpty ? message : 'Queued for the main PC';
      case 'node':
        final where = text == 'worker'
            ? ((label ?? '').isNotEmpty ? label! : 'a worker PC')
            : 'this PC';
        return 'Reasoning on $where';
      case 'search':
        return 'Searched: ${answer ?? ''}';
      case 'fetch_more':
        return 'Read more of a document';
      case 'expand_file':
        return 'Read a whole document';
      case 'read_original':
        return 'Re-read the original file';
      case 'error':
        return (message ?? '').isNotEmpty ? message : 'Something went wrong';
      default:
        return null;
    }
  }
}

enum ChatStatus { idle, sending }

/// Immutable chat screen state.
class ChatState {
  final List<ChatMessage> messages;
  final int conversationId; // 0 = new
  final ChatStatus status;
  final String step; // legacy single-line progress label (superseded by [trail])

  /* WHERE THE TRAIL LIVES, AND WHY.
     The web draws the trail inside the assistant bubble. This app draws it in the
     strip just above the input bar, where the old single step line already was, and
     keeps it in ChatState rather than on the ChatMessage. Three reasons:
       - it is turn progress, not turn content. The bubble holds what survives the
         turn (answer, sources, surfaces); the trail is about the wait.
       - a trail that grows inside a ListView item fights the autoscroll: every new
         step changes the item's height under a list that is animating to its end.
         Above the input bar the height change is local and the answer does not move.
       - on a phone the bubble is already the scarce space, and the trail is exactly
         the thing you want visible while you are NOT reading an answer yet.
     The cost, stated plainly: only the CURRENT turn has a trail. Scrolling back to
     an older turn shows no "3 steps · 6.4s" summary, where the web does. */
  final List<ChatStep> trail;

  /// Seconds the last turn took, for the collapsed trail summary.
  final double elapsed;

  /// The trail is finished (every line closed, transients dropped) and collapses.
  final bool trailDone;

  /// Stop was pressed and the running turn has not ended yet. The server only checks its stop
  /// flag between decision rounds, so this can last a few seconds.
  final bool stopping;

  const ChatState({
    this.messages = const [],
    this.conversationId = 0,
    this.status = ChatStatus.idle,
    this.step = '',
    this.trail = const [],
    this.elapsed = 0,
    this.trailDone = false,
    this.stopping = false,
  });

  bool get sending => status == ChatStatus.sending;

  ChatState copyWith({
    List<ChatMessage>? messages,
    int? conversationId,
    ChatStatus? status,
    String? step,
    List<ChatStep>? trail,
    double? elapsed,
    bool? trailDone,
    bool? stopping,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        conversationId: conversationId ?? this.conversationId,
        status: status ?? this.status,
        step: step ?? this.step,
        trail: trail ?? this.trail,
        elapsed: elapsed ?? this.elapsed,
        trailDone: trailDone ?? this.trailDone,
        stopping: stopping ?? this.stopping,
      );
}
