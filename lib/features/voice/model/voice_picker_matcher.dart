/// Which of the options on screen did the user just say?
///
/// People answer a picker three ways: by position ("the second one", "doosra", "number 3",
/// "last"), by name ("Acme Exports", "exports wala"), or not at all (a new question). This
/// returns the option's index for the first two and null for the third — and null whenever
/// two options fit equally well, because picking the wrong client is worse than asking again.
library;

const _ordinals = <int, List<String>>{
  0: ['first', '1st', 'one', 'pehla', 'pehli', 'pahla', 'pahli', 'pehle', 'पहला', 'पहली', 'पहले', 'ek', 'एक'],
  1: ['second', '2nd', 'two', 'doosra', 'dusra', 'doosri', 'dusri', 'दूसरा', 'दूसरी', 'do', 'दो'],
  2: ['third', '3rd', 'three', 'teesra', 'tisra', 'teesri', 'tisri', 'तीसरा', 'तीसरी', 'teen', 'तीन'],
  3: ['fourth', '4th', 'four', 'chautha', 'chauthi', 'चौथा', 'चौथी', 'char', 'चार'],
  4: ['fifth', '5th', 'five', 'paanchva', 'panchva', 'paanchvi', 'पांचवा', 'पांचवीं', 'paanch', 'पांच'],
};

const _last = ['last', 'aakhri', 'akhri', 'aakhiri', 'आखिरी', 'last wala', 'last one'];

/// Words that carry no identity ("the", "wala", "one", "company"...) — ignored when matching
/// a spoken name against a label.
const _filler = {
  'the', 'a', 'an', 'one', 'wala', 'wali', 'vala', 'vali', 'use', 'select', 'choose', 'pick',
  'option', 'number', 'no', 'please', 'that', 'this', 'vo', 'wo', 'woh', 'ye', 'yeh', 'ka',
  'ki', 'ke', 'hai', 'client', 'firm', 'company', 'and', 'co', 'pvt', 'ltd', 'private',
  'limited', 'file', 'वाला', 'वाली', 'का', 'की', 'है',
};

/// Index into [labels] of the option [utterance] names, or null.
int? matchOption(String utterance, List<String> labels) {
  if (labels.isEmpty) return null;
  final said = _norm(utterance);
  if (said.isEmpty) return null;
  final words = said.split(' ');

  // By position. A bare digit counts ("2", "number 2"); an ordinal WORD counts only in a
  // short reply — "do" is Hindi for two, and also the start of "do it tomorrow".
  final digit = RegExp(r'^(?:number |no |option )?(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(said);
  if (digit != null) {
    final i = int.parse(digit.group(1)!) - 1;
    return (i >= 0 && i < labels.length) ? i : null;
  }
  if (words.length <= 4) {
    if (_last.any((w) => _hasPhrase(said, w))) return labels.length - 1;
    int? byOrdinal;
    for (final e in _ordinals.entries) {
      if (e.key >= labels.length) continue;
      if (e.value.any((w) => _hasPhrase(said, w))) {
        if (byOrdinal != null && byOrdinal != e.key) return null; // "first or second?"
        byOrdinal = e.key;
      }
    }
    if (byOrdinal != null && !_namesAny(words, labels)) return byOrdinal;
  }

  // By name: the share of a label's DISTINCTIVE name words that were said. Only the name part
  // counts ("Acme Holdings — Retail group" is named "Acme Holdings"), and a word every option
  // shares ("Acme" in three Acmes) identifies nothing, so it is left out of every score.
  final saidSet = words.where((w) => !_filler.contains(w)).toSet();
  if (saidSet.isEmpty) return null;
  final names = [
    for (final l in labels)
      _norm(l.split(' — ').first).split(' ').where((w) => w.isNotEmpty && !_filler.contains(w)).toSet()
  ];
  final shared = names.length > 1
      ? names.skip(1).fold<Set<String>>(names.first, (a, b) => a.intersection(b))
      : <String>{};
  var best = -1;
  var bestScore = 0.0;
  var tie = false;
  for (var i = 0; i < labels.length; i++) {
    final distinct = names[i].difference(shared);
    final lw = distinct.isEmpty ? names[i] : distinct;
    if (lw.isEmpty) continue;
    var hit = 0;
    for (final w in lw) {
      if (saidSet.any((s) => s == w || (s.length >= 4 && w.startsWith(s)) || (w.length >= 4 && s.startsWith(w)))) {
        hit++;
      }
    }
    final score = hit / lw.length;
    if (score > bestScore) {
      bestScore = score;
      best = i;
      tie = false;
    } else if (score == bestScore && score > 0) {
      tie = true;
    }
  }
  if (best < 0 || tie || bestScore < 0.5) return null;
  return best;
}

bool _namesAny(List<String> words, List<String> labels) {
  final said = words.where((w) => !_filler.contains(w) && w.length >= 3).toSet();
  for (final l in labels) {
    for (final w in _norm(l).split(' ')) {
      if (w.length >= 3 && !_filler.contains(w) && said.contains(w)) return true;
    }
  }
  return false;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _hasPhrase(String text, String phrase) => ' $text '.contains(' ${_norm(phrase)} ');
