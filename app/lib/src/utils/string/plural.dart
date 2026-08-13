/// The plural of [word] for a count of [n] — `plural(1, 'file')` is `file`,
/// `plural(0, 'file')` is `files`.
///
/// One spelling, because there were five. The app had a correct private helper
/// inside the JSON view and four hand-rolled ternaries elsewhere
/// (`n == 1 ? 'file' : 'files'`, `file${n == 1 ? '' : 's'}`, …), which is how
/// the assets panel came to say "1 assets" — nobody forgot the rule, there was
/// simply nothing to reach for.
///
/// Pass [ifPlural] for words English does not pluralise with a bare `s`:
/// `plural(n, 'entry', ifPlural: 'entries')`.
String plural(int n, String word, {String? ifPlural}) =>
    n == 1 ? word : (ifPlural ?? '${word}s');

/// [n] and its unit together: `1 file`, `3 files`.
String counted(int n, String word, {String? ifPlural}) =>
    '$n ${plural(n, word, ifPlural: ifPlural)}';
