/// What the user can answer BY VOICE when the assistant puts a question on screen.
///
/// The server never sends a voice-specific payload: it composes one A2UI surface and both
/// clients draw it. So the voice layer reads the same surface — the picker's options and the
/// button that submits them, a confirm card's two buttons, a row of chips — and turns each
/// option into exactly the [A2uiAction] a tap would have produced ([routeA2uiAction]). A spoken
/// "the second one" and a tap on the second row send the same sentence, which is the only way
/// the two can never disagree.
library;

import 'dart:convert';

import '../../chat/model/a2ui_actions.dart';
import '../../chat/model/chat_models.dart';

/// One answer the user can say.
class VoiceOption {
  const VoiceOption(this.label, this.action);

  /// What is shown (and read out).
  final String label;

  /// What choosing it does — the same action the tap sends.
  final A2uiAction action;
}

/// A question on screen with a fixed set of answers.
class VoiceChoices {
  const VoiceChoices({required this.question, required this.options});
  final String question;
  final List<VoiceOption> options;
}

/// A write waiting for Confirm / Cancel.
class VoiceConfirm {
  const VoiceConfirm({
    required this.name,
    required this.args,
    required this.summary,
    this.warnings = const [],
  });
  final String name;
  final Map<String, dynamic> args;
  final String summary;
  final List<String> warnings;

  /// Sends something to someone outside the firm. A spoken yes to these gets a short spoken
  /// cancel window first (CommitRouter: send_invoice, chase_missing_documents with to=client).
  bool get outbound =>
      (name == 'send_invoice' || name == 'chase_missing_documents') && args['to'] == 'client';
}

/// The pending confirm on [m], from the legacy proposal or the A2UI confirm surface.
VoiceConfirm? confirmOf(ChatMessage m) {
  final p = m.confirm;
  if (p != null && p.name.isNotEmpty) {
    return VoiceConfirm(
        name: p.name, args: p.commitArgs, summary: p.summary, warnings: p.warnings);
  }
  for (final comps in _componentSets(m.a2ui)) {
    for (final c in comps.values) {
      final ev = _event(c);
      if (ev?.name != 'docsync.commit') continue;
      final routed = routeA2uiAction(ev!.name, ev.context);
      if (routed is! CommitWrite) continue;
      final texts = comps.values
          .where((x) => x['component'] == 'Text' && x['id'] != 'title' && !_isLabel(comps, x))
          .toList();
      final summary = texts.isNotEmpty ? '${texts.first['text'] ?? ''}' : '';
      final warnings = texts.skip(1).map((x) => '${x['text'] ?? ''}').toList();
      return VoiceConfirm(
          name: routed.action, args: routed.args, summary: summary, warnings: warnings);
    }
  }
  return null;
}

/// The answerable question on [m]'s surfaces, or null. Multi-select pickers are offered as
/// single choices by voice (one name at a time is what people say); the screen still allows
/// several.
VoiceChoices? choicesOf(ChatMessage m) {
  for (final comps in _componentSets(m.a2ui)) {
    // 1. A picker plus the button that submits its bound value.
    for (final picker in comps.values.where((c) => c['component'] == 'ChoicePicker')) {
      final path = _path(picker['value']);
      final submit = comps.values.map(_event).whereType<_Event>().firstWhere(
            (e) => e.context.values.any((v) => _path(v) == path && path != null),
            orElse: () => const _Event('', {}),
          );
      if (submit.name.isEmpty) continue;
      final opts = <VoiceOption>[];
      for (final o in (picker['options'] as List? ?? const [])) {
        if (o is! Map) continue;
        final value = '${o['value'] ?? ''}';
        if (value.isEmpty) continue;
        final ctx = <String, Object?>{
          for (final e in submit.context.entries)
            e.key: _path(e.value) == path ? [value] : e.value,
        };
        opts.add(VoiceOption('${o['label'] ?? value}', routeA2uiAction(submit.name, ctx)));
      }
      if (opts.isNotEmpty) {
        return VoiceChoices(question: _question(comps), options: opts);
      }
    }
    // 2. Buttons that each carry their whole answer (next-step chips, undo, list rows).
    final chips = <VoiceOption>[];
    for (final c in comps.values.where((c) => c['component'] == 'Button')) {
      final ev = _event(c);
      if (ev == null || ev.name == 'docsync.commit' || ev.name == 'docsync.cancel') continue;
      if (ev.context.values.any((v) => _path(v) != null)) continue; // needs a bound value
      final action = routeA2uiAction(ev.name, ev.context);
      if (action is ActionFailed) continue;
      chips.add(VoiceOption(_labelOf(comps, c), action));
    }
    if (chips.isNotEmpty) return VoiceChoices(question: _question(comps), options: chips);
  }
  return null;
}

// ---------------------------------------------------------------------------- internals

class _Event {
  const _Event(this.name, this.context);
  final String name;
  final Map<String, Object?> context;
}

/// Every surface's components, id → component, in arrival order. A later update of the same
/// surface replaces the earlier one.
List<Map<String, Map<String, dynamic>>> _componentSets(List<Map<String, dynamic>> msgs) {
  final bySurface = <String, Map<String, Map<String, dynamic>>>{};
  for (final m in msgs) {
    final u = m['updateComponents'];
    if (u is! Map) continue;
    final id = '${u['surfaceId'] ?? ''}';
    final comps = bySurface.putIfAbsent(id, () => {});
    for (final c in (u['components'] as List? ?? const [])) {
      if (c is Map && c['id'] != null) comps['${c['id']}'] = Map<String, dynamic>.from(c);
    }
  }
  return bySurface.values.toList();
}

_Event? _event(Map<String, dynamic> c) {
  final a = c['action'];
  if (a is! Map) return null;
  final ev = a['event'];
  if (ev is! Map || ev['name'] == null) return null;
  final ctx = ev['context'];
  return _Event('${ev['name']}', ctx is Map ? Map<String, Object?>.from(ctx) : {});
}

String? _path(Object? v) => (v is Map && v['path'] is String) ? v['path'] as String : null;

bool _isLabel(Map<String, Map<String, dynamic>> comps, Map<String, dynamic> text) =>
    comps.values.any((c) => c['child'] == text['id']);

String _labelOf(Map<String, Map<String, dynamic>> comps, Map<String, dynamic> button) {
  final child = comps['${button['child'] ?? ''}'];
  final t = child?['text'];
  if (t is String && t.isNotEmpty) return t;
  final ev = _event(button);
  final label = ev?.context['label'];
  return label is String && label.isNotEmpty ? label : 'this option';
}

String _question(Map<String, Map<String, dynamic>> comps) {
  final q = comps['q']?['text'];
  if (q is String && q.isNotEmpty) return q;
  for (final c in comps.values) {
    if (c['component'] == 'Text' && !_isLabel(comps, c) && c['text'] is String) {
      return c['text'] as String;
    }
  }
  return '';
}

/// For tests and logs: a stable text form of an action.
String describeAction(A2uiAction a) => switch (a) {
      SendChat(:final text) => 'send: $text',
      CommitWrite(:final action, :final args) => 'commit: $action ${jsonEncode(args)}',
      CancelWrite(:final action) => 'cancel: $action',
      OpenPage(:final url) => 'open: $url',
      ActionFailed(:final message) => 'failed: $message',
    };
