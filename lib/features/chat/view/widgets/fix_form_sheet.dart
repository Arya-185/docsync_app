import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/chat_controller.dart';
import '../../model/a2ui_actions.dart';
import 'a2ui_docsync_catalog.dart';

/// "Enter information" (server M4): the detail an action stopped on — a client's email, GSTIN,
/// PAN or mobile, a billing address, a task's fee — typed into a sheet over the chat.
///
/// The app half of the web's form popup, speaking the same `ai_fix.php` protocol: `schema`
/// describes the fields, `cities` fills the city list once a state is chosen, `save` writes. The
/// values typed here go ONLY to that endpoint. They are encrypted columns the model is never
/// shown, so they never pass through the chat, and none ever comes back: a field already on file
/// says "on file" and stays empty.
///
/// Resolves to the server's "Saved …" message when something was saved, or null.
class FixFormSheet extends ConsumerStatefulWidget {
  const FixFormSheet({super.key, required this.request});

  final FormRequest request;

  static Future<String?> show(BuildContext context, FormRequest request) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        // Keep the Save button above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: FixFormSheet(request: request),
      ),
    );
  }

  @override
  ConsumerState<FixFormSheet> createState() => _FixFormSheetState();
}

class _FixFormSheetState extends ConsumerState<FixFormSheet> {
  Map<String, dynamic>? _schema;
  String _loadError = '';
  bool _saving = false;
  String _formError = '';
  Map<String, String> _errors = const {};

  final Map<String, TextEditingController> _text = {};
  final Map<String, String?> _choice = {};
  final Map<String, List<Map<String, dynamic>>> _options = {};

  Map<String, String> get _base => {
        'form': widget.request.form,
        'ids': widget.request.ids,
        'need': widget.request.need,
      };

  List<Map<String, dynamic>> get _fields => (_schema?['fields'] as List? ?? const [])
      .whereType<Map>()
      .map((f) => Map<String, dynamic>.from(f))
      .where((f) => '${f['name'] ?? ''}'.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await ref.read(chatRepositoryProvider).fix({'op': 'schema', ..._base});
    if (!mounted) return;
    if (res['ok'] != true || res['fields'] is! List) {
      setState(() => _loadError = '${res['message'] ?? 'That could not be done just now.'}');
      return;
    }
    setState(() {
      _schema = res;
      for (final f in _fields) {
        final name = '${f['name']}';
        if (f['type'] == 'select') {
          _choice[name] = null;
          _options[name] = _optionList(f['options']);
        } else {
          _text[name] = TextEditingController(text: f['value'] == null ? '' : '${f['value']}');
        }
      }
    });
  }

  static List<Map<String, dynamic>> _optionList(Object? raw) => (raw is List ? raw : const [])
      .whereType<Map>()
      .map((o) => Map<String, dynamic>.from(o))
      .where((o) => (int.tryParse('${o['id']}') ?? 0) > 0)
      .toList();

  /// A select that depends on [parent] (city on state) is refilled when it changes.
  Future<void> _parentChanged(String parent, String? value) async {
    final deps = _fields.where((f) => f['depends'] == parent).map((f) => '${f['name']}').toList();
    setState(() {
      _choice[parent] = value;
      for (final d in deps) {
        _choice[d] = null;
        _options[d] = const [];
      }
    });
    if (value == null || deps.isEmpty) return;
    final res = await ref.read(chatRepositoryProvider).fix({'op': 'cities', 'state': value});
    if (!mounted || _choice[parent] != value) return;
    setState(() {
      for (final d in deps) {
        _options[d] = res['ok'] == true ? _optionList(res['options']) : const [];
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    // The same check the web form makes before posting: a required field left empty.
    final missing = <String, String>{};
    for (final f in _fields) {
      if (f['required'] != true) continue;
      final name = '${f['name']}';
      final v = f['type'] == 'select' ? (_choice[name] ?? '') : _text[name]?.text.trim() ?? '';
      if (v.isEmpty) missing[name] = 'This is needed.';
    }
    if (missing.isNotEmpty) {
      setState(() {
        _errors = missing;
        _formError = 'Please fill in the highlighted ${missing.length > 1 ? 'fields' : 'field'}.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
      _formError = '';
    });
    final body = <String, String>{'op': 'save', ..._base};
    for (final f in _fields) {
      final name = '${f['name']}';
      body[name] = f['type'] == 'select' ? (_choice[name] ?? '') : _text[name]?.text.trim() ?? '';
    }
    final res = await ref.read(chatRepositoryProvider).fix(body);
    if (!mounted) return;
    if (res['ok'] == true) {
      Navigator.of(context).pop('${res['message'] ?? 'Saved.'}');
      return;
    }
    final errs = res['errors'] is Map
        ? (res['errors'] as Map).map((k, v) => MapEntry('$k', '$v'))
        : <String, String>{};
    setState(() {
      _saving = false;
      _errors = errs;
      _formError = '${res['message'] ?? 'That could not be saved just now.'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final schema = _schema;
    final title = '${schema?['title'] ?? 'Enter information'}';
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(title: title),
          Flexible(
            child: schema == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: _loadError.isNotEmpty
                        ? Text(_loadError, style: const TextStyle(color: Color(0xFFB42318)))
                        : const Row(children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('Loading…', style: TextStyle(color: Color(0xFF475467))),
                          ]),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ('${schema['intro'] ?? ''}'.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text('${schema['intro']}',
                                style: const TextStyle(fontSize: 13.5, color: Color(0xFF475467))),
                          ),
                        for (final f in _fields) _field(f),
                        if (_formError.isNotEmpty)
                          Text(_formError,
                              style: const TextStyle(fontSize: 13, color: Color(0xFFB42318))),
                      ],
                    ),
                  ),
          ),
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: A2.line))),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: A2.muted),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: schema == null || _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: A2.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('${schema?['submit'] ?? 'Save'}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(Map<String, dynamic> f) {
    final name = '${f['name']}';
    final type = '${f['type'] ?? 'text'}';
    final required = f['required'] == true;
    final onFile = f['on_file'] == true;
    final error = _errors[name];
    final placeholder = '${f['placeholder'] ?? ''}';
    final max = int.tryParse('${f['max'] ?? ''}');
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
    );
    InputDecoration deco({String? hint}) => InputDecoration(
          isDense: true,
          hintText: hint ?? (placeholder.isEmpty ? null : placeholder),
          errorText: error,
          counterText: '',
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: const BorderSide(color: A2.indigo, width: 1.5)),
        );

    Widget input;
    if (type == 'select') {
      final parent = '${f['depends'] ?? ''}';
      final waiting = parent.isNotEmpty && _choice[parent] == null;
      final opts = _options[name] ?? const [];
      final parentLabel = _fields
          .firstWhere((x) => x['name'] == parent, orElse: () => const {})['label'];
      input = DropdownButtonFormField<String>(
        key: ValueKey('$name-${_choice[parent] ?? ''}-${opts.length}'),
        initialValue: _choice[name],
        isExpanded: true,
        decoration: deco(
          hint: waiting
              ? 'Choose the ${'${parentLabel ?? parent}'.toLowerCase()} first'
              : (opts.isEmpty && parent.isNotEmpty ? 'None listed' : 'Choose…'),
        ),
        items: [
          for (final o in opts)
            DropdownMenuItem(
              value: '${o['id']}',
              child: Text('${o['name']}', overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: waiting
            ? null
            : (v) {
                if (_errors.containsKey(name)) _errors = Map.of(_errors)..remove(name);
                final hasDependents = _fields.any((x) => x['depends'] == name);
                if (hasDependents) {
                  _parentChanged(name, v);
                } else {
                  setState(() => _choice[name] = v);
                }
              },
      );
    } else {
      input = TextField(
        controller: _text[name],
        autofocus: f['focus'] == true,
        maxLength: max != null && max > 0 ? max : null,
        maxLines: type == 'textarea' ? 3 : 1,
        minLines: type == 'textarea' ? 3 : 1,
        keyboardType: switch (type) {
          'email' => TextInputType.emailAddress,
          'tel' => TextInputType.phone,
          'money' => const TextInputType.numberWithOptions(decimal: true),
          'textarea' => TextInputType.multiline,
          _ => TextInputType.text,
        },
        textCapitalization:
            f['upper'] == true ? TextCapitalization.characters : TextCapitalization.none,
        autocorrect: false,
        textInputAction: type == 'textarea' ? TextInputAction.newline : TextInputAction.next,
        // An error is about what WAS typed; typing again takes it away.
        onChanged: (_) {
          if (_errors.containsKey(name)) setState(() => _errors = Map.of(_errors)..remove(name));
        },
        decoration: deco(),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text.rich(TextSpan(
                  text: '${f['label'] ?? name}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: A2.navy),
                  children: [
                    if (required)
                      const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFB42318))),
                  ],
                )),
                if (onFile)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F6EE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('on file',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF0F7B4D))),
                  ),
              ],
            ),
          ),
          input,
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: A2.line))),
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 2),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: A2.line, borderRadius: BorderRadius.circular(2)),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: A2.navy),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: A2.muted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
