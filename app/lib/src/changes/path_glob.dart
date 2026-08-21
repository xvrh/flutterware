/// Matching a repository-relative path against an `attention:` pattern, **the
/// way `.gitignore` does it** rather than the way `package:glob` does.
///
/// The three anchoring rules everybody already has in their fingers, and which
/// `package:glob` alone does not give (measured — the falses are what a user
/// writes, believes, and never sees fire):
///
/// | pattern | path | `package:glob` |
/// |---|---|---|
/// | `**/*.g.dart` | `a.g.dart` | **no** — a leading `**/` may match nothing |
/// | `*.sql` | `db/a.sql` | **no** — no separator means a name, at any depth |
/// | `build/` | `build/x.dill` | **no** — a trailing `/` is a prefix |
///
/// A pattern is therefore compiled to up to three spellings, matched as
/// alternatives rather than rewritten to whichever one we guessed was meant.
///
/// Pure Dart — `fw changes` ranks with the same rules the GUI does.
library;

import 'package:glob/glob.dart';

/// The project's `attention:` patterns, compiled once and matched many times.
class PathGlobSet {
  PathGlobSet(Iterable<String> patterns)
    : _compiled = [
        for (var pattern in patterns)
          if (_compile(pattern) case var globs when globs.isNotEmpty)
            (pattern: pattern, globs: globs),
      ];

  /// Each pattern exactly as the user wrote it — it is shown on the row it
  /// pinned — beside the spellings it compiled to.
  final List<({String pattern, List<Glob> globs})> _compiled;

  bool get isEmpty => _compiled.isEmpty;

  /// The first pattern matching [path] — repository-relative, `/`-separated —
  /// or null.
  ///
  /// First rather than any, because the caller shows it: a row that says
  /// *pinned by* has to name one rule, and naming the earliest one makes the
  /// answer a function of the order the user wrote them in.
  ///
  /// Matching is against the *whole* relative path, never an absolute one:
  /// git's own vocabulary, and the only spelling every caller here has.
  String? firstMatch(String path) {
    var normalized = _normalize(path);
    if (normalized.isEmpty) return null;
    for (var (:pattern, :globs) in _compiled) {
      for (var glob in globs) {
        if (glob.matches(normalized)) return pattern;
      }
    }
    return null;
  }

  /// The spellings [pattern] can match by. Empty for a pattern that will not
  /// compile, which is how a stray `[` costs that rule and nothing else — the
  /// probe runs inside an isolate, and an exception mid-refresh would lose the
  /// file list to a typo in an attention rule.
  static List<Glob> _compile(String pattern) {
    var cleaned = _normalize(pattern);
    if (cleaned.isEmpty) return const [];

    // A directory pattern is a prefix, expanded first so the rules below see
    // the expanded form rather than the trailing slash.
    if (cleaned.endsWith('/')) cleaned = '$cleaned**';

    var spellings = {
      cleaned,
      if (!cleaned.contains('/')) '**/$cleaned',
      if (cleaned.startsWith('**/')) cleaned.substring(3),
    };

    return [
      for (var spelling in spellings)
        // `recursive: false` because `**` is written where it is meant. The
        // recursive flag silently appends one, which would make `lib` match
        // every file under `lib/` — a pattern the user did not write.
        ?_tryCompile(spelling),
    ];
  }

  static Glob? _tryCompile(String pattern) {
    try {
      return Glob(pattern, recursive: false);
    } on Object {
      return null;
    }
  }

  /// Separators to `/`, and no leading `./` — so a pattern written on Windows
  /// and a path read from git meet in the same alphabet.
  static String _normalize(String value) {
    var normalized = value.replaceAll(r'\', '/').trim();
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }
}
