/// What a project says about its own changes — which files matter, and what
/// the delta is measured against.
///
/// Declared in `tool/flutterware.dart` like everything else:
///
/// ```dart
/// void main() => Flutterware.configure((fw) {
///   fw.changes(ChangesConfig(
///     attention: ['lib/api/**', 'tool/flutterware.dart'],
///     base: 'develop',
///   ));
///   fw.use(Previews());
/// });
/// ```
///
/// **There is no second config file and no second way of reading this one.**
/// The Dart config is the point: static analysis, autocomplete, and a type
/// error instead of a typo that silently matches nothing.
///
/// Plain data, and deliberately so — nothing here knows how to match a glob.
/// This type crosses to a CLI, a cache file and an isolate, and the matcher
/// lives where the matching happens.
library;

/// A project's ranking rules for the changes screen.
class ChangesConfig {
  const ChangesConfig({this.attention = const [], this.base});

  /// Paths worth looking at first, as globs — the changes screen's *Important*
  /// tab. Each pinned row names the pattern that pinned it, so precedence is
  /// inspectable rather than magic.
  ///
  /// **There is no built-in list, and there must not be one.** flutterware
  /// does not know what matters in your repository, and putting a file under a
  /// heading that says *look here first* is a claim only you can make.
  ///
  /// Matching follows the rules everybody already knows from `.gitignore`: a
  /// pattern with no `/` matches a file of that name at any depth, and a
  /// leading `**/` also matches at the repository root.
  final List<String> attention;

  /// The branch the delta is measured from.
  ///
  /// Only needed when inference fails: `origin/HEAD`, then `main`, then
  /// `master` is tried first, and a worktree where one of those resolves does
  /// not need this. Nothing is ever diffed against a guess.
  final String? base;

  bool get isEmpty => attention.isEmpty && base == null;

  Map<String, Object?> toJson() => {
    if (attention.isNotEmpty) 'attention': attention,
    'base': ?base,
  };

  /// **Tolerant of everything except a wrong shape.** This is read back from a
  /// cache file that a previous version of flutterware wrote, so an entry that
  /// is not a string is dropped rather than thrown on — the alternative is a
  /// screen that refuses to rank because one list had a number in it.
  static ChangesConfig fromJson(Map<String, Object?> json) => ChangesConfig(
    attention: _strings(json['attention']),
    base: json['base'] as String?,
  );

  /// **A type test, never a cast.** `as String?` would throw on the entry it is
  /// supposed to be tolerating, which is a tolerance that only holds for input
  /// that never needed it — and a value that is not a list at all must not
  /// throw either.
  static List<String> _strings(Object? value) => [
    if (value is List)
      for (var entry in value)
        if (entry is String) entry,
  ];

  @override
  bool operator ==(Object other) =>
      other is ChangesConfig &&
      other.base == base &&
      _same(other.attention, attention);

  @override
  int get hashCode => Object.hash(base, attention.length);

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
