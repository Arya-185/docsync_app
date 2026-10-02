import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/config.dart';
import '../../../core/network/api_client.dart';
import 'chat_models.dart';

class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  /// Follow a turn that is already running on the server, reconnecting until it ends.
  ///
  /// A turn belongs to the conversation, not to the client that started it: it keeps running
  /// after the app is backgrounded or killed, and it may have been started on the web. Opening
  /// such a chat attaches here and receives the events that were missed, then the rest as they
  /// happen.
  ///
  /// `rag_stream.php` speaks the SAME contract as `rag_answer.php`, so these events go through
  /// the identical [RagEvent.fromJson] and the identical fold in ChatController — there is no
  /// second rendering path to keep in step.
  ///
  /// The server hands its PHP worker back every couple of minutes so a few open chats cannot
  /// exhaust the pool; it says so with `resume_end.status == "running"` and the sequence number
  /// reached, and reconnecting from there is this method's job. The resume bookkeeping is
  /// consumed here so callers see only real turn events.
  Stream<RagEvent> followStream(int conv, {int after = 0, CancelToken? cancel}) async* {
    var cursor = after;
    for (var attempt = 0; attempt < 40; attempt++) {
      if (cancel?.isCancelled ?? false) return;
      final Response<ResponseBody> resp;
      try {
        resp = await _api.dio.get<ResponseBody>(
          _api.url('/app/rag_stream.php'),
          queryParameters: {'conv': conv, 'after': cursor},
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: AppConfig.answerTimeout,
            headers: {'Accept': 'text/event-stream'},
          ),
        );
      } on DioException catch (e) {
        yield RagEvent(RagEventType.error, message: _dioMessage(e));
        return;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        yield const RagEvent(RagEventType.error, message: 'not_authenticated');
        return;
      }

      var live = false;
      var ended = false;
      final lines = resp.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final raw in lines) {
        final line = raw.trimRight();
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        Map<String, dynamic>? obj;
        try {
          obj = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final kind = obj['type'];
        if (kind == 'resume') {
          live = obj['status'] == 'running';
          continue;
        }
        if (kind == 'resume_end') {
          cursor = (obj['seq'] as num?)?.toInt() ?? cursor;
          ended = obj['status'] != 'running';
          continue;
        }
        yield RagEvent.fromJson(obj);
      }

      // Nothing was running after all: the turn finished between the chat opening and this
      // connecting. The caller reloads the transcript rather than waiting on nothing.
      if (!live) return;
      if (ended) return;
    }
  }

  /// Ask AI. Streams [RagEvent]s parsed from the SSE response of rag_answer.php.
  /// [conv] = 0 starts a new conversation.
  ///
  /// [voice] asks the server for a reply meant to be SPOKEN (short, no tables or markdown);
  /// [lang] is the language the user spoke, as reported by speech-to-text, so the reply matches
  /// it. Both are only sent when set, so an older server simply ignores a request that has none.
  Stream<RagEvent> answerStream(
    String query, {
    int conv = 0,
    int k = AppConfig.defaultK,
    bool voice = false,
    String? lang,
    CancelToken? cancel,
  }) async* {
    final Response<ResponseBody> resp;
    try {
      resp = await _api.dio.post<ResponseBody>(
        _api.url('/app/rag_answer.php'),
        data: {
          'query': query,
          'k': k,
          'conv': conv,
          if (voice) 'voice': 1,
          if (voice && lang != null && lang.isNotEmpty) 'lang': lang,
        },
        cancelToken: cancel,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.stream,
          receiveTimeout: AppConfig.answerTimeout,
          headers: {'Accept': 'text/event-stream'},
        ),
      );
    } on DioException catch (e) {
      yield RagEvent(RagEventType.error, message: _dioMessage(e));
      return;
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      yield const RagEvent(RagEventType.error, message: 'not_authenticated');
      return;
    }

    final lines = resp.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final raw in lines) {
      final line = raw.trimRight();
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      Map<String, dynamic>? obj;
      try {
        obj = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final ev = RagEvent.fromJson(obj);
      yield ev;
      /* DO NOT add `confirm` here, however terminal it looks. A confirm turn ends
         WITHOUT a `final` (AskAiAgent.php returns straight after emitting it), but
         `usage` still follows and the `a2ui` messages that draw the confirmation
         card sit around it — breaking here would throw the card away. Nothing
         hangs: PHP closes the response, so this `await for` ends on its own.
         Breaking on `final` stays correct: a picker's `a2ui` messages precede it. */
      if (ev.type == RagEventType.finalAnswer ||
          ev.type == RagEventType.error ||
          ev.type == RagEventType.unavailable) {
        break;
      }
    }
  }

  /// POST a confirmed `[high_write]` action to ai_commit.php.
  ///
  /// `conv` lets the server record the created entity against this chat so a later
  /// "change that task" can resolve it. Ownership, ACL and row existence are all
  /// re-derived server-side from the live session, so a forged value only fails
  /// closed.
  ///
  /// NO `Origin` HEADER, DELIBERATELY. ai_commit.php's same-origin guard is
  /// permissive only when both `Origin` and `Referer` are absent — which is exactly
  /// what dio sends — so the app can commit today. Setting a mismatched `Origin`
  /// would turn a working call into a 403. `X-DocSync-App` marks the app instead,
  /// so the loophole can be closed server-side once this build is out.
  ///
  /// [key] is the card's proposal key when the reply carried several (server M5); the server
  /// then commits THAT card's stored arguments and records it as answered. Sent only when set,
  /// so a lone card posts exactly what it always did.
  Future<CommitResult> commit(
    String action,
    Map<String, dynamic> args, {
    int conv = 0,
    String key = '',
  }) async {
    try {
      final r = await _api.dio.post(
        _api.url('/app/ai_commit.php'),
        // `args` is a JSON STRING on the wire, but it is an OBJECT in
        // [ConfirmProposal]; encoding it twice is a `bad_request`.
        data: {
          'action': action,
          'args': jsonEncode(args),
          'conv': conv,
          if (key.isNotEmpty) 'key': key,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'X-DocSync-App': '1'},
        ),
      );
      final body = _asMap(r.data);
      if (body == null) {
        return const CommitResult(false, 'Could not complete the action.');
      }
      final msg = (body['message'] ?? '').toString();
      if (body['ok'] == true) {
        return CommitResult(true, msg.isNotEmpty ? msg : 'Done.');
      }
      return CommitResult(
          false, msg.isNotEmpty ? msg : 'Could not complete the action.');
    } on DioException catch (e) {
      return CommitResult(false, _dioMessage(e));
    } catch (_) {
      return const CommitResult(false, 'Request failed.');
    }
  }

  /// Draw a preview (server M3): `ai_preview.php` answers `{ok, title, html}` — a whole,
  /// self-contained document (the logo is inlined) — or `{ok: false, message}`.
  ///
  /// Read-only on the server: it re-checks the session and the module grant, re-derives the
  /// draft from the card's own arguments, and numbers, writes and sends nothing.
  Future<PreviewResult> preview(Map<String, String> fields) async {
    final body = await _postForm('/app/ai_preview.php', fields,
        failed: 'The preview could not be drawn just now.');
    final html = body['html'];
    if (body['ok'] == true && html is String && html.isNotEmpty) {
      return PreviewResult(true, title: '${body['title'] ?? 'Preview'}', html: html);
    }
    return PreviewResult(false,
        message: '${body['message'] ?? 'The preview could not be drawn just now.'}');
  }

  /// "Enter information" (server M4): `op` is `schema`, `cities` or `save`.
  ///
  /// The values typed into the form go ONLY here — straight to the session-checked endpoint,
  /// never into the chat, so an email or a PAN never reaches the model. And none comes back: a
  /// field already on file is reported as `on_file`, never with its value.
  Future<Map<String, dynamic>> fix(Map<String, String> fields) =>
      _postForm('/app/ai_fix.php', fields, failed: 'That could not be done just now.');

  /// POST a form and read a JSON object back, whatever the status: these endpoints answer
  /// 400/403 with `{ok: false, message}` meant for the user.
  Future<Map<String, dynamic>> _postForm(String path, Map<String, String> fields,
      {required String failed}) async {
    try {
      final r = await _api.dio.post(
        _api.url(path),
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'X-DocSync-App': '1'},
        ),
      );
      final body = _asMap(r.data);
      if (body != null) return body;
      return {
        'ok': false,
        'message': r.statusCode == 401 ? 'Please sign in again.' : failed,
      };
    } on DioException catch (e) {
      return {'ok': false, 'message': _dioMessage(e)};
    } catch (_) {
      return {'ok': false, 'message': failed};
    }
  }

  /// Ask the server to stop the turn running on [conv]. True when a running turn was flagged.
  ///
  /// `rag_stop.php` only raises a flag: the agent checks it before its next decision round and
  /// then ends with a `final` carrying `stopped: true`. So the stream keeps going briefly after
  /// this returns, and the UI says "Stopping…" until it ends — the same as the web page.
  Future<bool> stop(int conv) async {
    if (conv <= 0) return false;
    try {
      final r = await _api.dio.post(
        _api.url('/app/rag_stop.php'),
        data: {'conv': conv},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final body = _asMap(r.data);
      return body != null && body['ok'] == true && body['stopped'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Note that the user has now read this chat, clearing its unread mark.
  ///
  /// Called on opening AND when a turn finishes on screen. The second is not redundant:
  /// opening a chat whose turn is still running marks it read, and the answer then lands after
  /// that moment — so the chat being watched would mark itself unread the instant it replied.
  ///
  /// Fire-and-forget. A failed mark costs a dot that clears next time; it must never surface
  /// as an error over a chat that is working perfectly well.
  Future<void> markSeen(int conv) async {
    if (conv <= 0) return;
    try {
      await _api.dio.post(
        _api.url('/app/rag_seen.php'),
        data: {'conv': conv},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } catch (_) {
      // deliberately ignored
    }
  }

  Future<List<Conversation>> listConversations() async {
    try {
      final r = await _api.dio.get(
        _api.url('/app/rag_conversations.php'),
        queryParameters: {'action': 'list'},
      );
      final body = _asMap(r.data);
      if (body == null || body['ok'] != true) return const [];
      return (body['conversations'] as List?)
              ?.map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<ChatMessage>> conversationMessages(int id) async {
    try {
      final r = await _api.dio.get(
        _api.url('/app/rag_conversations.php'),
        queryParameters: {'action': 'messages', 'c': id},
      );
      final body = _asMap(r.data);
      if (body == null || body['ok'] != true) return const [];
      return (body['messages'] as List?)
              ?.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final d = jsonDecode(data);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return null;
  }

  String _dioMessage(DioException e) {
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'The request timed out. The service may be busy.';
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Cannot reach the server.';
    }
    return 'Request failed: ${e.message ?? e.type.name}';
  }
}
