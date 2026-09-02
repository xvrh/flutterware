/// Whether a `file` selector picks [declared] — that path exactly, or any path
/// under it as a directory.
///
/// A folder is the unit of work in a scenario suite and always was: device and
/// language profiles are declared per folder in `flutter_test_config.dart`,
/// and a CI job runs a line per folder because of it. Only the selector
/// disagreed, and "run this folder's scenarios" fell back to bare
/// `flutter test` — reported by a consumer with a four-folder suite.
///
/// Separator-anchored, so `test/app/checkout` never picks up
/// `test/app/checkout_archive/…`. Trailing slashes are tolerated because a
/// shell completes a directory with one.
///
/// Several selectors arrive as one string, comma-separated — `a_test.dart,b/`
/// — which is how `--file=a --file=b` and `--file=a,b` both look by the time
/// they get here. [fileSelectors] is the split, kept beside the predicate so
/// the harness and the plugin cut on the same comma; the predicate itself
/// takes one selector, so a caller can still say *which* of them matched
/// nothing — a typo in the second file must not run green on the strength of
/// the first.
///
/// Its own file, with nothing above it: the harness half runs inside the
/// user's test process and the plugin half counts and refuses against the
/// same rule, and the two disagreeing is a run that reports the wrong total
/// or refuses what it would have run.
library;

bool selectsFile(String selector, String declared) {
  if (selector == declared) return true;
  var directory = selector.endsWith('/')
      ? selector.substring(0, selector.length - 1)
      : selector;
  return declared.startsWith('$directory/');
}

/// The selectors in a `file` argument, in the order they were given —
/// which is the order a run that names several files runs them in.
List<String> fileSelectors(String selector) => [
  for (var one in selector.split(','))
    if (one.trim().isNotEmpty) one.trim(),
];

/// Whether any selector in a `file` argument picks [declared].
bool anySelectsFile(String selectors, String declared) =>
    fileSelectors(selectors).any((one) => selectsFile(one, declared));
