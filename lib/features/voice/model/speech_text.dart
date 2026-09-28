/// Turning answer text into something worth saying out loud.
///
/// Two jobs. [speakable] strips what a screen shows but a voice must not read ("asterisk
/// asterisk", a URL spelled out, a table as a wall of pipes). [SentenceChunker] cuts the
/// streaming answer into whole sentences as they complete, so the first one can be spoken
/// while the rest is still being written — the difference between a reply that starts in a
/// second and one that starts when the whole answer is done.
library;

/// Plain, speakable text from chat markdown.
String speakable(String text) {
  var t = text;
  t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  t = t.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!);
  t = t.replaceAll(RegExp(r'https?://\S+'), '');
  t = t.replaceAll(RegExp(r'^\s{0,3}(#{1,6}|[-*+>]|\d+[.)])\s+', multiLine: true), '');
  t = t.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
  // A table row reads better as a list of values than as "pipe".
  t = t.replaceAll(RegExp(r'^\s*\|?[\s:|-]+\|?\s*$', multiLine: true), ''); // |---|---|
  t = t.replaceAll('|', ', ');
  t = t.replaceAllMapped(
      RegExp(r'(?<!\w)[*_](\S[^*_]*\S|\S)[*_](?!\w)'), (m) => m[1]!);
  // A line break inside the answer is a pause, not a run-on.
  t = t.replaceAllMapped(RegExp(r'([^.!?।:\s])\s*\n+'), (m) => '${m[1]}. ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'(,\s*){2,}'), ', ');
  return t.replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '').trim();
}

/// Cuts a growing answer into sentences to speak, and stops talking after [maxChars].
///
/// A voice-mode answer is already short (the server asks for one to three sentences). A
/// templated answer — a list of twenty tasks — is not, and reading all of it aloud is worse
/// than useless when the list is on screen. So speech stops at the budget and says where
/// the rest is.
class SentenceChunker {
  SentenceChunker({this.maxChars = 420, this.minChunk = 24});

  final int maxChars;

  /// Very short sentences ("Done.") are joined to the next rather than sent alone: every
  /// chunk is a TTS round trip.
  final int minChunk;

  static const overflowNote = 'The rest is on your screen.';

  String _raw = '';
  int _consumed = 0; // chars of the speakable text already emitted
  int _spoken = 0;
  bool _capped = false;

  bool get capped => _capped;

  /// The whole answer so far (not a delta: the chat state holds the full text, and an answer
  /// can be replaced wholesale at `final`). Returns the sentences that are now complete.
  List<String> update(String fullText) {
    _raw = fullText;
    return _drain(flush: false);
  }

  /// The answer is complete: whatever is left is the last sentence.
  List<String> finish([String? fullText]) {
    if (fullText != null) _raw = fullText;
    return _drain(flush: true);
  }

  List<String> _drain({required bool flush}) {
    if (_capped) return const [];
    final text = speakable(_raw);
    // The answer was rewritten (e.g. `final` replaced it) and no longer extends what was
    // spoken: never re-say it, just carry on from the same length.
    if (_consumed > text.length) _consumed = text.length;
    var rest = text.substring(_consumed);
    final out = <String>[];

    while (true) {
      final m = RegExp(r'^(.*?[.!?।])(\s+|$)').firstMatch(rest);
      String? piece;
      int take = 0;
      if (m != null && (m.end < rest.length || flush)) {
        piece = m.group(1)!;
        take = m.end;
        // Join a too-short sentence with the next complete one, if there is one yet.
        while (piece!.length < minChunk) {
          final n = RegExp(r'^(.*?[.!?।])(\s+|$)').firstMatch(rest.substring(take));
          if (n == null || (take + n.end >= rest.length && !flush)) break;
          piece = '$piece ${n.group(1)!}';
          take += n.end;
        }
      } else if (flush && rest.trim().isNotEmpty) {
        piece = rest.trim();
        take = rest.length;
      }
      if (piece == null || piece.trim().isEmpty) break;

      if (_spoken + piece.length > maxChars && _spoken > 0) {
        _capped = true;
        out.add(overflowNote);
        break;
      }
      out.add(piece.trim());
      _spoken += piece.length;
      _consumed += take;
      rest = rest.substring(take);
    }
    return out;
  }
}
