import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:genui/genui.dart';

import '../../model/a2ui_tone.dart';

/// DocSync's look for the server-built surfaces: the Dart half of the server repo's
/// `app/assets/css/ai-a2ui.css`.
///
/// genui's stock items draw Material defaults — a grey elevated card, stadium buttons, headings
/// at headline size — and none of that is DocSync. The server cannot fix it: the A2UI schema is
/// strict, so a component carries no class or style. The web styles them from the surface's
/// KIND (its id's prefix) and each component's id, and this catalog does the same thing in the
/// same places, so one surface reads the same on a phone as in a browser:
///
///   - headings (`head`, `title`, `q`) in navy, captions upright and muted;
///   - a results list as ONE grouped container, a chevron row per record, a status pill coloured
///     from its word, a red edge on a high-priority row, and "Show N more" past [visibleRows];
///   - facts as tiles; link cards with an indigo edge, "Enter information" cards with an amber one;
///   - a confirm as an amber box with ⚠ warnings and its buttons on the right;
///   - next steps and Undo as pill chips; questions in a white box.
///
/// Every item keeps the stock item's name and schema, so the catalog id the server names in
/// createSurface still resolves here, and anything this file does not recognise falls back to
/// the stock widget rather than drawing nothing.
Catalog docSyncCatalog() {
  final base = BasicCatalogItems.asNoAssetCatalog();
  CatalogItem stock(String name) => base.items.firstWhere((i) => i.name == name);
  return base.copyWith(newItems: [
    _wrap(stock('Text'), _text),
    _wrap(stock('Button'), _button),
    _wrap(stock('Card'), _card),
    _wrap(stock('Column'), _column),
    _wrap(stock('Row'), _row),
    _wrap(stock('List'), _list),
    _wrap(stock('ChoicePicker'), _themed),
    _wrap(stock('DateTimeInput'), _themed),
  ]);
}

/// The web stylesheet's tokens (`.ai-a2ui { --ds-* }`).
abstract final class A2 {
  static const indigo = Color(0xFF4154F1);
  static const indigo600 = Color(0xFF3445D6);
  static const indigo50 = Color(0xFFEEF0FE);
  static const chipLine = Color(0xFFC7CDF9);
  static const navy = Color(0xFF012970);
  static const ink = Color(0xFF1F2937);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE6E9EF);
  static const chevron = Color(0xFF98A2B3);
  static const tile = Color(0xFFF8F9FC);
  static const amber = Color(0xFFF79009);
  static const amberLine = Color(0xFFF5D9A8);
  static const amberBg = Color(0xFFFFFCF5);
  static const warn = Color(0xFF9A5B00);
  static const red = Color(0xFFF04438);
  static const radius = 12.0;

  /// A status pill's (text, background) for a tone from [toneFor].
  static (Color, Color) tone(String tone) => switch (tone) {
        'success' => (const Color(0xFF0F7B4D), const Color(0xFFE7F6EE)),
        'info' => (const Color(0xFF3445D6), const Color(0xFFEEF0FE)),
        'warn' => (const Color(0xFF9A5B00), const Color(0xFFFFF4E0)),
        'danger' => (const Color(0xFFB42318), const Color(0xFFFDECEA)),
        _ => (const Color(0xFF475467), const Color(0xFFF2F4F7)),
      };
}

typedef _Build = Widget Function(CatalogItemContext c, Widget Function() stock);

CatalogItem _wrap(CatalogItem base, _Build build) => CatalogItem(
      name: base.name,
      dataSchema: base.dataSchema,
      widgetBuilder: (c) => build(c, () => base.widgetBuilder(c)),
      exampleData: base.exampleData,
      isImplicitlyFlexible: base.isImplicitlyFlexible,
    );

final _rowLabel = RegExp(r'^l\d+$');
final _rowMeta = RegExp(r'^m\d+$');
final _rowStatus = RegExp(r'^s\d+$');
final _rowTitleLine = RegExp(r'^t\d+$');
final _rowButton = RegExp(r'^a\d+$');
final _rowCard = RegExp(r'^c\d+$');
final _fact = RegExp(r'^f\d+$');

/// A button's own label ("yes_label", "next_label_0", "submit_label").
bool _isLabel(String id) => id.endsWith('_label') || id.contains('_label_');

JsonMap _data(CatalogItemContext c) => c.data as JsonMap;

List<String>? _childIds(Object? children) =>
    children is List ? children.map((e) => '$e').toList() : null;

// ---------------------------------------------------------------------------------- text

Widget _text(CatalogItemContext c, Widget Function() stock) {
  final data = _data(c);
  final kind = surfaceKind(c.surfaceId);
  final id = c.id;
  final caption = data['variant'] == 'caption';
  final value = data['text'];
  if (value == null) return stock();

  return BoundString(
    dataContext: c.dataContext,
    value: value,
    builder: (context, raw) {
      final text = raw ?? '';
      if (kind == 'list' && _rowStatus.hasMatch(id)) return TonePill(text);

      final base = DefaultTextStyle.of(context).style;
      final style = _textStyle(kind, id, caption, base);
      final shown = kind == 'confirm' && id.startsWith('warn') ? '⚠ $text' : text;
      final body = MarkdownBody(
        data: shown,
        softLineBreak: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: style,
          strong: style.copyWith(fontWeight: FontWeight.w700),
          // Captions are facts ("Client: …", "due 13 Apr"), not asides: upright, as on the web.
          em: style.copyWith(fontStyle: FontStyle.normal),
        ),
      );
      if (kind == 'facts' && _fact.hasMatch(id)) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: A2.tile,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: A2.line),
          ),
          child: body,
        );
      }
      return body;
    },
  );
}

TextStyle _textStyle(String kind, String id, bool caption, TextStyle base) {
  if (id == 'head' || id == 'title' || id == 'q') {
    return base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: A2.navy, height: 1.35);
  }
  // Inside a button: the button decides the colour (white on indigo, indigo on a chip).
  if (_isLabel(id)) {
    return base.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3);
  }
  if (_rowLabel.hasMatch(id)) {
    return base.copyWith(fontSize: 14.4, fontWeight: FontWeight.w600, color: A2.ink, height: 1.35);
  }
  if (kind == 'confirm' && id.startsWith('warn')) {
    return base.copyWith(fontSize: 13, color: A2.warn, height: 1.45);
  }
  if (kind == 'confirm' && id == 'summary') {
    return base.copyWith(fontSize: 14.4, color: A2.ink, height: 1.4);
  }
  if (caption || _rowMeta.hasMatch(id) || (kind == 'list' && (id == 'facts' || id == 'more'))) {
    return base.copyWith(fontSize: 12.8, color: A2.muted, height: 1.45);
  }
  if (kind == 'facts' && _fact.hasMatch(id)) {
    return base.copyWith(fontSize: 13.6, color: A2.ink, height: 1.4);
  }
  return base.copyWith(fontSize: 14.5, color: A2.ink, height: 1.4);
}

/// A results row's status word as a coloured pill (the web's `[data-tone]`).
class TonePill extends StatelessWidget {
  const TonePill(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = A2.tone(toneFor(text));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg, height: 1.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------- buttons

Widget _button(CatalogItemContext c, Widget Function() stock) {
  final data = _data(c);
  final action = data['action'];
  final childId = data['child'];
  // Only plain event actions are drawn here — every one the server sends. Anything else (a
  // client function, validation checks) keeps genui's own behaviour.
  if (action is! Map || action['event'] is! Map || childId is! String || data['checks'] != null) {
    return stock();
  }
  final child = c.buildChild(childId);
  final variant = '${data['variant'] ?? ''}';
  final kind = surfaceKind(c.surfaceId);

  Future<void> press() async {
    final event = Map<String, Object?>.from(action['event'] as Map);
    final ctx = event['context'];
    final resolved = await resolveContext(
      c.dataContext,
      ctx is Map ? Map<String, Object?>.from(ctx) : null,
    );
    c.dispatchEvent(UserActionEvent(
      name: '${event['name']}',
      sourceComponentId: c.id,
      context: resolved,
    ));
  }

  // A results row: full width, left aligned, a chevron at the end. The Card is its only edge.
  if (variant == 'borderless' && (kind == 'list' || _rowButton.hasMatch(c.id))) {
    return TextButton(
      onPressed: press,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        foregroundColor: A2.ink,
        shape: const RoundedRectangleBorder(),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        children: [
          Expanded(child: child),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 20, color: A2.chevron),
        ],
      ),
    );
  }

  // Anywhere else a borderless button is a chip: next steps, Undo.
  if (variant == 'borderless') {
    return TextButton(
      onPressed: press,
      style: TextButton.styleFrom(
        foregroundColor: A2.indigo,
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(side: BorderSide(color: A2.chipLine)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: child,
    );
  }

  final primary = variant == 'primary';
  return ElevatedButton(
    onPressed: press,
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: primary ? A2.indigo : Colors.white,
      foregroundColor: primary ? Colors.white : A2.ink,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      minimumSize: const Size(0, 38),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: primary ? BorderSide.none : const BorderSide(color: A2.line),
      ),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    ),
    child: child,
  );
}

// ---------------------------------------------------------------------------------- cards

Widget _card(CatalogItemContext c, Widget Function() stock) {
  final childId = _data(c)['child'];
  if (childId is! String) return stock();
  final child = c.buildChild(childId);
  final kind = surfaceKind(c.surfaceId);

  // A row of a results list: no edge of its own — the list is one grouped container.
  if (kind == 'list' && _rowCard.hasMatch(c.id)) {
    final n = c.id.substring(1);
    final meta = c.getComponent('m$n')?.properties['text'];
    final tappable = c.getComponent(childId)?.type == 'Button';
    Widget body = tappable
        ? child
        : Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: child);
    if (isHighPriority(meta is String ? meta : null)) {
      body = Stack(children: [
        body,
        Positioned(
          left: 0,
          top: 10,
          bottom: 10,
          width: 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: A2.red,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
            ),
          ),
        ),
      ]);
    }
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: body,
    );
  }

  final accent = switch (kind) { 'link' => A2.indigo, 'fix' => A2.amber, _ => null };
  return Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(A2.radius),
      side: const BorderSide(color: A2.line),
    ),
    child: Container(
      width: double.infinity,
      decoration: accent == null
          ? null
          : BoxDecoration(border: Border(left: BorderSide(color: accent, width: 3))),
      padding: kind == 'facts'
          ? const EdgeInsets.fromLTRB(16, 14, 16, 16)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------------- columns

Widget _column(CatalogItemContext c, Widget Function() stock) {
  final kind = surfaceKind(c.surfaceId);
  final id = c.id;

  // Facts: the title across the top, then the figures as tiles, as many to a line as fit.
  if (kind == 'facts' && id == 'body') {
    final ids = _childIds(_data(c)['children']);
    if (ids == null) return stock();
    return LayoutBuilder(builder: (context, box) {
      const gap = 10.0;
      final w = box.maxWidth.isFinite ? box.maxWidth : 300.0;
      final cols = math.max(1, ((w + gap) / (150 + gap)).floor());
      final tileW = (w - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final k in ids)
            SizedBox(width: _fact.hasMatch(k) ? tileW : w, child: c.buildChild(k)),
        ],
      );
    });
  }

  if (id != 'root') return stock();
  // The proposal: an amber box, so a write waiting on the user cannot be mistaken for an answer.
  if (kind == 'confirm') {
    return _box(
      stock(),
      color: A2.amberBg,
      border: Border(
        left: const BorderSide(color: A2.amber, width: 4),
        top: const BorderSide(color: A2.amberLine),
        right: const BorderSide(color: A2.amberLine),
        bottom: const BorderSide(color: A2.amberLine),
      ),
    );
  }
  // A question: a white box holding the question, its choices and the answer button.
  if (const {'pick', 'many', 'choose', 'when'}.contains(kind)) {
    return _box(stock(), color: Colors.white, border: Border.all(color: A2.line));
  }
  return stock();
}

Widget _box(Widget child, {required Color color, required Border border}) {
  // A Material, not a coloured DecoratedBox: the pickers inside are ListTiles, which paint their
  // ink on the nearest Material and are hidden by a coloured box in between. A non-uniform
  // border cannot take a radius in Flutter, so the left edge is drawn as a bar inside the
  // rounded, clipped shape — the same picture as the web's border-left on a radius.
  final uniform = border.isUniform;
  return SizedBox(
    width: double.infinity,
    child: Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(A2.radius),
        side: BorderSide(color: border.top.color),
      ),
      child: uniform
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: child)
          : Container(
              decoration: BoxDecoration(border: Border(left: border.left)),
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: child,
            ),
    ),
  );
}

// ---------------------------------------------------------------------------------- rows

Widget _row(CatalogItemContext c, Widget Function() stock) {
  final ids = _childIds(_data(c)['children']);
  if (ids == null) return stock();
  final kind = surfaceKind(c.surfaceId);
  final id = c.id;
  Widget kid(String k) => c.buildChild(k);

  // A results row's title line: the label takes the room, the status pill sits at the end.
  if (_rowTitleLine.hasMatch(id) && ids.length == 2) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: kid(ids[0])),
        const SizedBox(width: 10),
        kid(ids[1]),
      ],
    );
  }
  // Next steps: chips that wrap onto a second line rather than overflow.
  if (kind == 'next' && id == 'root') {
    return Wrap(spacing: 8, runSpacing: 8, children: [for (final k in ids) kid(k)]);
  }
  // A confirm's buttons: on the right; on a narrow screen they share the width.
  if (kind == 'confirm' && id == 'buttons') {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth.isFinite && box.maxWidth < 420) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            for (var i = 0; i < ids.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: kid(ids[i])),
            ],
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final k in ids) kid(k)]),
        ),
      );
    });
  }
  // A card's own buttons (Preview + Open invoice; Enter information + Open page).
  if (id == 'actions') {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 8, children: [for (final k in ids) kid(k)]),
    );
  }
  return stock();
}

// ---------------------------------------------------------------------------------- lists

Widget _list(CatalogItemContext c, Widget Function() stock) {
  final ids = _childIds(_data(c)['children']);
  if (surfaceKind(c.surfaceId) != 'list' || ids == null) return stock();
  return ResultRows(ids: ids, build: (k) => c.buildChild(k));
}

/// A results list: one bordered container, a hairline between rows, and the rows past
/// [visibleRows] behind "Show N more".
class ResultRows extends StatefulWidget {
  const ResultRows({super.key, required this.ids, required this.build});
  final List<String> ids;
  final Widget Function(String id) build;

  @override
  State<ResultRows> createState() => _ResultRowsState();
}

class _ResultRowsState extends State<ResultRows> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total = widget.ids.length;
    final long = total > visibleRows;
    final shown = long && !_expanded ? widget.ids.take(visibleRows).toList() : widget.ids;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(A2.radius),
            border: Border.all(color: A2.line),
            boxShadow: const [BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: A2.line),
                widget.build(shown[i]),
              ],
            ],
          ),
        ),
        if (long)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(moreLabel(total - visibleRows, _expanded)),
                iconAlignment: IconAlignment.end,
                style: OutlinedButton.styleFrom(
                  foregroundColor: A2.indigo,
                  side: const BorderSide(color: A2.line),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------- inputs

/// Pickers and date fields keep genui's own widgets (their data binding is the delicate part),
/// in DocSync's indigo.
Widget _themed(CatalogItemContext c, Widget Function() stock) {
  return Builder(builder: (context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme.copyWith(primary: A2.indigo, onPrimary: Colors.white);
    return Theme(
      data: t.copyWith(
        colorScheme: scheme,
        listTileTheme: t.listTileTheme.copyWith(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          selectedTileColor: A2.indigo50,
        ),
        inputDecorationTheme: t.inputDecorationTheme.copyWith(
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: A2.indigo, width: 1.5),
          ),
        ),
      ),
      child: stock(),
    );
  });
}
