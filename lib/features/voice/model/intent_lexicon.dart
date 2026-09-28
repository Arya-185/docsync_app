/// What a short spoken reply means when the app has just asked a yes/no question
/// ("Shall I go ahead?") or is talking and hears the user cut in.
///
/// Deliberately a word list, not a model: a false "yes" writes to a client's records, so the
/// rule has to be one a person can read. A reply is only a yes if it is SHORT, contains an
/// affirmative, and contains no negation — "haan nahi", "yes but don't send it" and "no wait
/// yes" are all [unclear], and unclear is asked again, never guessed.
library;

enum ReplyIntent {
  yes,
  no,

  /// "Stop" / "ruko" / "bas": stop talking (and, while confirming, the same as no).
  stop,

  /// Not a yes/no at all — probably a new request.
  other,

  /// A yes/no that could not be told apart. Ask again.
  unclear,
}

/// Longer than this and it is a new request, not an answer.
const _maxReplyWords = 7;

const _yes = <String>[
  'yes', 'yeah', 'yep', 'yup', 'ya', 'ok', 'okay', 'sure', 'confirm', 'confirmed',
  'go ahead', 'do it', 'proceed', 'correct', 'right', 'please do', 'send it', 'go on',
  'haan', 'haa', 'han', 'ha', 'haanji', 'haan ji', 'ji', 'ji haan', 'theek hai', 'thik hai',
  'theek', 'thik', 'kar do', 'kardo', 'karo', 'bhej do', 'bhejdo', 'chalega', 'bilkul',
  'हाँ', 'हां', 'हा', 'जी', 'जी हाँ', 'ठीक है', 'कर दो', 'करो', 'भेज दो', 'बिल्कुल', 'चलेगा',
];

const _no = <String>[
  'no', 'nope', 'nah', 'cancel', 'dont', "don't", 'do not', 'not now', 'never mind',
  'nahi', 'nahin', 'nai', 'na', 'mat', 'mat karo', 'mat bhejo', 'rehne do', 'rahne do',
  'cancel karo', 'cancel kar do', 'nako',
  'नहीं', 'नही', 'ना', 'मत', 'मत करो', 'मत भेजो', 'रहने दो', 'कैंसल',
];

const _stop = <String>[
  'stop', 'wait', 'hold on', 'enough', 'quiet', 'shut up', 'pause',
  'ruko', 'ruk', 'ruk jao', 'bas', 'bas karo', 'chup', 'chup karo',
  'रुको', 'रुक', 'बस', 'बस करो', 'चुप',
];

/// Classify a transcript given as a reply.
ReplyIntent classifyReply(String transcript) {
  final t = _norm(transcript);
  if (t.isEmpty) return ReplyIntent.unclear;
  final words = t.split(' ');
  final isYes = _hasAny(t, _yes);
  final isNo = _hasAny(t, _no);
  final isStop = _hasAny(t, _stop);

  if (words.length > _maxReplyWords) return ReplyIntent.other;
  if (isStop && !isYes) return ReplyIntent.stop;
  if (isNo && isYes) return ReplyIntent.unclear;
  if (isNo) return ReplyIntent.no;
  if (isYes) return ReplyIntent.yes;
  // A short reply that is neither — "the second one", "tomorrow" — is not a yes/no.
  return ReplyIntent.other;
}

/// True when [transcript] is just "stop" in some form — used while the app is talking, where
/// anything else the user says is a new question.
bool isStopCommand(String transcript) {
  final t = _norm(transcript);
  if (t.isEmpty || t.split(' ').length > 3) return false;
  return _hasAny(t, _stop) || t == 'cancel' || t == 'no';
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Whole-word (or whole-phrase) match, so "ha" does not match inside "hai" or "chahiye".
bool _hasAny(String text, List<String> phrases) {
  final padded = ' $text ';
  for (final p in phrases) {
    if (padded.contains(' ${_norm(p)} ')) return true;
  }
  return false;
}
