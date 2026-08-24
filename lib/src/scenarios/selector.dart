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
