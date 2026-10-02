/// What the web stylesheet reads off a surface, as plain Dart.
///
/// The server's components carry no class names or styles (the A2UI schema is strict), so the
/// web decorates them from two things only: the surface's KIND (the surfaceId's prefix) and each
/// component's id. These are the Dart ports of `toneFor`, `moreLabel` and `VISIBLE_ROWS` in the
/// server repo's `web/src/a2ui-docsync.js`, kept free of Flutter imports so they can be tested
/// directly — two renderers deciding the same colour from the same word must agree.
library;

/// Rows a results list shows before "Show N more".
const visibleRows = 8;

/// A surface's kind: list, facts, link, fix, confirm, pick, many, choose, when, undo, next.
String surfaceKind(String surfaceId) {
  final i = surfaceId.indexOf('_');
  return i < 0 ? surfaceId : surfaceId.substring(0, i);
}

/// The status word of a results row as a tone: success, info, warn, danger or neutral.
String toneFor(String? text) {
  final t = (text ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return 'neutral';
  if (RegExp(r'\b(overdue|unpaid|rejected|cancell?ed|failed|expired|lapsed)\b').hasMatch(t)) {
    return 'danger';
  }
  if (RegExp(r'\b(on hold|hold|partial|partially paid|waiting|awaiting|query|queried|due soon)\b')
      .hasMatch(t)) {
    return 'warn';
  }
  if (RegExp(r'\b(completed?|done|paid|closed|approved|received|filed|verified|active)\b')
      .hasMatch(t)) {
    return 'success';
  }
  if (RegExp(r'\b(allotted|assigned|pending|in progress|open|new|started|working|scheduled|sent)\b')
      .hasMatch(t)) {
    return 'info';
  }
  return 'neutral';
}

/// The expander's label for [hidden] rows.
String moreLabel(int hidden, bool expanded) =>
    expanded ? 'Show fewer' : 'Show ${hidden < 0 ? 0 : hidden} more';

/// A row's meta line says it is high priority ("High priority · due 25 Sep"). Read from the
/// words, as on the web, so the edge is all it becomes and the words stay readable anywhere.
bool isHighPriority(String? meta) => RegExp(
      r'(^|·\s*)(high|urgent|critical) priority\b',
      caseSensitive: false,
    ).hasMatch((meta ?? '').trim());
