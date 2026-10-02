/// Turning an A2UI widget action into something the app can do.
///
/// This is the Dart half of `web/src/a2ui-docsync.js` in the server repo, and the two MUST
/// agree: the server composes one surface and both clients render it, so a verb handled
/// differently here than on the web is the same surface behaving differently on a phone.
/// Everything that decides WHAT to send lives in this file, with no Flutter imports, so it can
/// be tested directly against the same fixtures the web uses.
///
/// The contract for every verb except `docsync.commit` is the same one the picker has always
/// had: **the answer goes back as an ordinary chat turn.** There is no new endpoint, and a user
/// whose client cannot draw the widget can type the same sentence by hand. That is what makes
/// these surfaces safe to add.
library;

import 'dart:convert';

import 'a2ui_navigate.dart';

/// What the app should do in response to a widget action.
sealed class A2uiAction {
  const A2uiAction();
}

/// Send [text] as an ordinary chat message.
class SendChat extends A2uiAction {
  const SendChat(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is SendChat && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'SendChat($text)';
}

/// POST a confirmed write to ai_commit.php.
///
/// [key] names WHICH card when one reply carries several (server M5: "invoice 812 and invoice
/// 815" is two confirm cards, `confirm_create_invoice_<key>`). It is '' for a lone card, exactly
/// as before, and is sent to ai_commit.php so the server commits that card's own arguments.
class CommitWrite extends A2uiAction {
  const CommitWrite(this.action, this.args, {this.key = ''});
  final String action;
  final Map<String, dynamic> args;
  final String key;

  @override
  String toString() => 'CommitWrite($action, $args${key.isEmpty ? '' : ', key: $key'})';
}

/// The user declined the proposal. Nothing is sent anywhere. [key] as for [CommitWrite], so
/// Cancel on one card leaves the others in the same reply alone.
class CancelWrite extends A2uiAction {
  const CancelWrite(this.action, {this.key = ''});
  final String action;
  final String key;

  @override
  bool operator ==(Object other) =>
      other is CancelWrite && other.action == action && other.key == key;
  @override
  int get hashCode => Object.hash(action, key);
  @override
  String toString() => 'CancelWrite($action${key.isEmpty ? '' : ', key: $key'})';
}

/// Draw a preview (server M3, `app/ai_preview.php`): what a confirm card would create or send,
/// or an invoice that exists. Read-only — nothing is numbered, written or sent.
class OpenPreview extends A2uiAction {
  const OpenPreview(this.request);
  final PreviewRequest request;

  @override
  bool operator ==(Object other) => other is OpenPreview && other.request == request;
  @override
  int get hashCode => request.hashCode;
  @override
  String toString() => 'OpenPreview($request)';
}

/// "Enter information" (server M4, `app/ai_fix.php`): the detail an action stopped on, typed
/// into a form here; once saved, [FormRequest.retry] is asked again so the action carries on.
class OpenForm extends A2uiAction {
  const OpenForm(this.request);
  final FormRequest request;

  @override
  bool operator ==(Object other) => other is OpenForm && other.request == request;
  @override
  int get hashCode => request.hashCode;
  @override
  String toString() => 'OpenForm($request)';
}

/// What a Preview button asks for: `{kind: 'draft', action, args}` for a confirm card (args is
/// the card's commit_args as JSON TEXT, posted as-is), or `{kind: 'invoice', id}`.
class PreviewRequest {
  const PreviewRequest.draft(this.action, this.args)
      : kind = 'draft',
        id = 0;
  const PreviewRequest.invoice(this.id)
      : kind = 'invoice',
        action = '',
        args = '';
  final String kind;
  final String action;
  final String args;
  final int id;

  /// The form fields ai_preview.php takes.
  Map<String, String> get fields => kind == 'invoice'
      ? {'kind': kind, 'id': '$id'}
      : {'kind': kind, 'action': action, 'args': args};

  @override
  bool operator ==(Object other) =>
      other is PreviewRequest &&
      other.kind == kind &&
      other.action == action &&
      other.args == args &&
      other.id == id;
  @override
  int get hashCode => Object.hash(kind, action, args, id);
  @override
  String toString() => kind == 'invoice' ? 'invoice #$id' : 'draft $action $args';
}

/// The forms "Enter information" may open (server `UiSurface::FIX_FORMS`).
const fixForms = ['client_contact', 'client_address', 'task_fee'];

/// A `docsync.form` context: which form, for which records ([ids] stays the comma list the
/// server sent), the field that is [need]ed, and the question to ask again once saved.
class FormRequest {
  const FormRequest({required this.form, required this.ids, this.need = '', this.retry = ''});
  final String form;
  final String ids;
  final String need;
  final String retry;

  @override
  bool operator ==(Object other) =>
      other is FormRequest &&
      other.form == form &&
      other.ids == ids &&
      other.need == need &&
      other.retry == retry;
  @override
  int get hashCode => Object.hash(form, ids, need, retry);
  @override
  String toString() => 'FormRequest($form, $ids, need: $need, retry: $retry)';
}

/// The Dart port of `previewRequest()` in web/src/a2ui-docsync.js. Null when the context is not
/// one of the two shapes — a draft of a known-looking action with an object for args, or an
/// invoice with a positive id.
PreviewRequest? previewRequest(Map<String, Object?> context) {
  final kind = firstValue(context['kind']);
  if (kind == 'invoice') {
    final id = int.tryParse(firstValue(context['id']).trim()) ?? 0;
    return id > 0 ? PreviewRequest.invoice(id) : null;
  }
  if (kind == 'draft') {
    final action = firstValue(context['action']);
    if (!RegExp(r'^[a-z_]{3,40}$').hasMatch(action)) return null;
    final raw = context['args'];
    final args = raw is String ? raw : jsonEncode(raw ?? const <String, Object?>{});
    try {
      if (jsonDecode(args) is! Map) return null;
    } catch (_) {
      return null;
    }
    return PreviewRequest.draft(action, args);
  }
  return null;
}

/// The Dart port of `formRequest()` in web/src/a2ui-docsync.js.
FormRequest? formRequest(Map<String, Object?> context) {
  final form = firstValue(context['form']);
  final ids = firstValue(context['ids']);
  if (!fixForms.contains(form) ||
      !RegExp(r'^[1-9]\d{0,9}(,[1-9]\d{0,9}){0,9}$').hasMatch(ids)) {
    return null;
  }
  final need = firstValue(context['need']);
  final retry = firstValue(context['retry']).trim();
  return FormRequest(
    form: form,
    ids: ids,
    need: RegExp(r'^[a-z_]{2,20}$').hasMatch(need) ? need : '',
    retry: retry.length > 500 ? retry.substring(0, 500) : retry,
  );
}

/// A confirm card's key (server `UiSurface::proposalKey`): 8 lowercase hex characters, or ''.
String proposalKey(Object? v) {
  final k = firstValue(v);
  return RegExp(r'^[a-f0-9]{8}$').hasMatch(k) ? k : '';
}

/// The surface a confirm card lives in: `confirm_<action>` alone, `confirm_<action>_<key>` when
/// it is one of several in a reply.
String confirmSurfaceId(String action, String key) =>
    key.isEmpty ? 'confirm_$action' : 'confirm_${action}_$key';

/// Open a DocSync web page (a link card's "Open page"). [url] is the relative
/// `open.php?kind=…&id=…` the server built, already checked against the allow-list.
class OpenPage extends A2uiAction {
  const OpenPage(this.url);
  final String url;

  @override
  bool operator ==(Object other) => other is OpenPage && other.url == url;
  @override
  int get hashCode => url.hashCode;
  @override
  String toString() => 'OpenPage($url)';
}

/// Something went wrong, or the verb is not one this build knows.
///
/// This exists so an unhandled verb is REPORTED. Both renderers previously matched on name and
/// fell off the end on a miss — a button that looks live, does nothing when pressed, and logs
/// nothing. Every new surface adds a verb, so the miss has to be loud.
class ActionFailed extends A2uiAction {
  const ActionFailed(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ActionFailed && other.message == message;
  @override
  int get hashCode => message.hashCode;
  @override
  String toString() => 'ActionFailed($message)';
}

/// Route one widget action. [name] is the action verb, [context] its bound values.
A2uiAction routeA2uiAction(String? name, Map<String, Object?> context) {
  switch (name) {
    case 'docsync.pick':
      final raw = firstValue(context['choice']);
      if (raw.isEmpty) return const ActionFailed('Nothing was selected.');
      final parts = _splitCandidate(raw);
      final kind = _str(context['kind'], 'item');
      return SendChat(parts.label.isNotEmpty
          ? 'Use $kind #${parts.id} — ${parts.label}.'
          : 'Use $kind #${parts.id}.');

    case 'docsync.pickMany':
      final sentence = manySentence(context['choice'], context['kind']);
      if (sentence.isEmpty) return const ActionFailed('Nothing was selected.');
      return SendChat(sentence);

    case 'docsync.date':
      final when = whenSentence(firstValue(context['when']));
      if (when.isEmpty) {
        return const ActionFailed('Pick a date or a time first.');
      }
      return SendChat(when);

    // No row id to name here -- these are a parameter's own allowed values (a status, a
    // priority), so the sentence names the PARAMETER. The value is passed through untouched
    // because it has to match the enum the tool schema declares; only the parameter name is
    // made readable.
    case 'docsync.choose':
      final value = firstValue(context['choice']);
      if (value.isEmpty) return const ActionFailed('Nothing was selected.');
      final param = _str(context['param'], 'value').replaceAll('_', ' ');
      return SendChat('Use $param: $value.');

    case 'docsync.open':
      final id = int.tryParse(_str(context['id'], '').trim()) ?? 0;
      if (id <= 0) return const ActionFailed('That row has nothing to open.');
      final kind = _str(context['kind'], 'item');
      final label = _str(context['label'], '');
      return SendChat(label.isNotEmpty
          ? 'Open $kind #$id — $label.'
          : 'Open $kind #$id.');

    case 'docsync.commit':
      // args arrive as a JSON STRING because A2UI's DynamicValue has no object variant.
      final rawArgs = context['args'];
      Map<String, dynamic> args;
      try {
        if (rawArgs is String) {
          args = rawArgs.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(jsonDecode(rawArgs) as Map);
        } else if (rawArgs is Map) {
          args = Map<String, dynamic>.from(rawArgs);
        } else {
          args = <String, dynamic>{};
        }
      } catch (_) {
        return const ActionFailed('Could not read the confirmation details.');
      }
      return CommitWrite(_str(context['action'], ''), args, key: proposalKey(context['key']));

    // A link card's "Open page" (server M5): the web page, in-app, on the app's session.
    case 'docsync.navigate':
      final url = context['url'];
      if (!isOpenUrl(url)) {
        return const ActionFailed('That link is not one this app follows.');
      }
      return OpenPage(url as String);

    case 'docsync.cancel':
      return CancelWrite(_str(context['action'], ''), key: proposalKey(context['key']));

    // Preview on a confirm card or an invoice card (server M3): drawn in a sheet on this screen.
    case 'docsync.preview':
      final req = previewRequest(context);
      if (req == null) return const ActionFailed('There is nothing to preview here.');
      return OpenPreview(req);

    // "Enter information" (server M4): the context names the form and its records, never a
    // value — what is typed goes straight to ai_fix.php, never into the chat or the model.
    case 'docsync.form':
      final req = formRequest(context);
      if (req == null) return const ActionFailed('There is nothing to fill in here.');
      return OpenForm(req);

    default:
      return ActionFailed(
        'This control is not supported by this app '
        '(${(name ?? '').isEmpty ? 'no action name' : name}).',
      );
  }
}

/// A ChoicePicker binds to a string LIST even when it is single-select, so a resolved value can
/// arrive as an array. Take the first entry and normalise to a string.
String firstValue(Object? v) {
  if (v is List) return v.isEmpty ? '' : '${v.first}';
  return v == null ? '' : '$v';
}

({String id, String label}) _splitCandidate(String raw) {
  final sep = raw.indexOf('|');
  if (sep < 0) return (id: raw, label: '');
  return (id: raw.substring(0, sep), label: raw.substring(sep + 1));
}

String _str(Object? v, String fallback) {
  if (v == null) return fallback;
  final s = '$v';
  return s.isEmpty ? fallback : s;
}

/// Several picked candidates as one sentence: "Use clients #12, #14 and #19."
///
/// The plural is naive on purpose — "client" becomes "clients", and a kind that does not
/// pluralise that way reads a little oddly rather than wrongly. What has to be exact is the set
/// of IDS, because that is what the model acts on. One selection falls back to the singular
/// rather than saying "clients #12".
///
/// Values arrive as `<id>|<label>` in selection order, and duplicates are dropped: a renderer
/// that reports the same value twice must not turn into the model being told to act twice.
String manySentence(Object? raw, Object? kind) {
  final list = raw is List
      ? raw
      : (raw == null || '$raw'.isEmpty ? const <Object?>[] : [raw]);
  final ids = <String>[];
  for (final v in list) {
    final s = '$v';
    final sep = s.indexOf('|');
    final id = (sep >= 0 ? s.substring(0, sep) : s).trim();
    if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
  }
  if (ids.isEmpty) return '';
  final noun = _str(kind, 'item');
  final hashed = ids.map((id) => '#$id').toList();
  if (hashed.length == 1) return 'Use $noun ${hashed.first}.';
  final last = hashed.removeLast();
  return 'Use ${noun}s ${hashed.join(', ')} and $last.';
}

/// Turn a DateTimeInput value into the sentence that goes back as an ordinary chat turn.
///
/// The widget writes three different shapes depending on which halves are enabled, and this was
/// read out of the renderer rather than guessed:
///
///   date only      2026-09-25
///   time only      17:00
///   both           2026-09-25T17:00:00      (and 2026-09-25T00:00:00 if only the date was set)
///
/// Seconds and any timezone suffix are dropped — the tools take 'YYYY-MM-DD' and 'HH:MM', and
/// handing DateResolver anything else just moves the parsing problem this widget exists to
/// remove. Returns '' when nothing was picked, so the caller can say so instead of sending a
/// bare "Use .".
String whenSentence(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return '';
  if (v.contains('T')) {
    final bits = v.split('T');
    final d = bits.isNotEmpty ? bits[0] : '';
    final t = bits.length > 1 ? bits[1] : '';
    final date = d.length >= 10 ? d.substring(0, 10) : d;
    final time = t.length >= 5 ? t.substring(0, 5) : t;
    if (date.isNotEmpty && time.isNotEmpty) return 'Use $date at $time.';
    if (date.isNotEmpty) return 'Use $date.';
    return time.isNotEmpty ? 'Use $time.' : '';
  }
  if (v.contains('-')) {
    return 'Use ${v.length >= 10 ? v.substring(0, 10) : v}.';
  }
  if (v.contains(':')) {
    return 'Use ${v.length >= 5 ? v.substring(0, 5) : v}.';
  }
  return '';
}

/// Which surface does this raw protocol message concern? Returns null when the message names
/// none — which is itself the answer, not an error.
String? surfaceIdOf(Map<String, dynamic> msg) {
  for (final key in const [
    'createSurface',
    'updateComponents',
    'updateDataModel',
    'deleteSurface',
  ]) {
    final body = msg[key];
    if (body is Map && body['surfaceId'] is String) {
      return body['surfaceId'] as String;
    }
  }
  return null;
}
