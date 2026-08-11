/// Matching a repository-relative path against a pattern, **the way
/// `.gitignore` does it** rather than the way `package:glob` does.
///
/// This is the one place a user's pattern meets a path, and it is worth its own
/// file because the naive version is silently wrong. Measured against
/// `package:glob` directly:
///
/// ```
/// **/*.g.dart        lib/a.g.dart       true
/// **/*.g.dart        a.g.dart           false   <-- surprising
/// **/migrations/**   db/migrations/1.sql  true
/// **/migrations/**   migrations/1.sql     false <-- surprising
/// *.sql              db/a.sql           false   <-- surprising
/// ```
///
/// Every one of those falses is a rule the user wrote, believed, and never saw
/// fire. **Silent non-matching is the exact failure the Dart config exists to
/// prevent**, so the two `.gitignore` anchoring rules everybody already has in
/// their fingers are implemented here:
///
/// 1. **A pattern with no `/` matches the file's name at any depth.** `*.sql`
///    catches `db/migrations/001.sql`, as it would in `.gitignore`.
/// 2. **A leading `**/` also matches at the root.** `**/*.g.dart` catches
///    `a.g.dart`, as it would in `.gitignore`.
/// 3. **A trailing `/` means the directory and everything under it.**
///    `build/` catches `build/app/x.dill`.
///
/// Pure Dart — `fw changes` ranks with the same rules the GUI does.
library;

import 'package:glob/glob.dart';

/// One user-written pattern, compiled once and matched many times.
class PathGlob {
  PathGlob(this.pattern) : _globs = _compile(pattern);

  /// Exactly what the user wrote. Shown on the row it pinned, so a rule that
  /// fired can be traced back to the line that wrote it.
  final String pattern;

  /// One pattern can need more than one glob: the anchoring rules above are
  /// alternatives, not rewrites, so `**/*.g.dart` compiles to both spellings
  /// rather than to whichever one we guessed the user meant.
  final List<Glob> _globs;

  /// True when [path] — repository-relative, `/`-separated — matches.
  ///
  /// Matching is against the *whole* relative path, never an absolute one:
  /// git's own vocabulary, and the only spelling every caller here has.
  bool matches(String path) {
    var normalized = _normalizePath(path);
    if (normalized.isEmpty) return false;
    for (var glob in _globs) {
      if (glob.matches(normalized)) return true;
    }
    return false;
  }

  static List<Glob> _compile(String pattern) {
    var cleaned = _normalizePath(pattern);
    if (cleaned.isEmpty) return const [];

    var spellings = <String>{};

    // Rule 3, first: a directory pattern is a prefix, and the rules below
    // should see the expanded form rather than the trailing slash.
    if (cleaned.endsWith('/')) cleaned = '$cleaned**';

    spellings.add(cleaned);

    // Rule 1 — no separator anywhere, so it is a name and not a path.
    if (!cleaned.contains('/')) spellings.add('**/$cleaned');

    // Rule 2 — `**/` may match nothing at all.
    if (cleaned.startsWith('**/')) spellings.add(cleaned.substring(3));

    return [
      for (var spelling in spellings)
        // `recursive: false` because `**` is written where it is meant. The
        // recursive flag silently appends one, which would make `lib` match
        // every file under `lib/` — a pattern the user did not write.
        ?_tryCompile(spelling),
    ];
  }

  /// A pattern that will not compile matches **nothing**, and says so by being
  /// empty rather than by throwing.
  ///
  /// A `ChangesConfig` is user code and this runs inside the probe: a stray
  /// `[` in one pattern must cost that pattern, not the whole screen. The
  /// alternative — an exception from an isolate mid-refresh — loses the file
  /// list to a typo in a noise rule.
  static Glob? _tryCompile(String pattern) {
    try {
      return Glob(pattern, recursive: false);
    } on Object {
      return null;
    }
  }

  /// Separators to `/`, and no leading `./` — so a pattern written on Windows
  /// and a path read from git meet in the same alphabet.
  static String _normalizePath(String value) {
    var normalized = value.replaceAll(r'\', '/').trim();
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }

  @override
  String toString() => pattern;
}

/// A list of patterns, matched as one.
class PathGlobSet {
  PathGlobSet(Iterable<String> patterns)
    : globs = [for (var pattern in patterns) PathGlob(pattern)];

  final List<PathGlob> globs;

  bool get isEmpty => globs.isEmpty;

  /// The first pattern that matches [path], or null.
  ///
  /// **First rather than any**, because the caller shows it: a row that says
  /// *pinned by* has to name one rule, and naming the earliest one makes the
  /// answer a function of the order the user wrote them in.
  String? firstMatch(String path) {
    for (var glob in globs) {
      if (glob.matches(path)) return glob.pattern;
    }
    return null;
  }
}
