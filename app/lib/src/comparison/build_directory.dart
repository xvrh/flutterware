import 'dart:io';

import 'package:path/path.dart' as p;

/// Where a comparison's harness runners build, one directory per claim.
///
/// The runners a comparison spawns cannot share `build/flutterware` with
/// anybody — and "anybody" is concrete on both sides. The **head** checkout is
/// the very worktree the panel's warm audit and scenario runners live on, and
/// `TesterHost.exclusive` serializes nothing across hosts: two hosts on one
/// directory are two `frontend_server`s writing one dill and two generators
/// pruning each other's wrappers. The **base** checkout is shared by every
/// comparison on the machine by design (`BaseCheckout` — five agents off one
/// master sha have one base between them), and only its *creation* is locked,
/// so even a constant name like `previews_compare` would collide the moment
/// two comparisons run against the same base at once. Hence per **claim**:
/// pid keeps processes apart, the counter keeps one process's concurrent
/// sessions apart.
const comparisonBuildRoot = 'build/flutterware/comparison';

var _claims = 0;

/// What marks a directory as a claim, and when it was made. Judged by its
/// mtime rather than the directory's because a directory's mtime moves with
/// every file the run writes into it — and cannot be aged by a test.
const _stamp = '.claim';

/// A directory under [comparisonBuildRoot] that no other run holds, relative to
/// [packageRoot]. Release it with [releaseComparisonBuildDirectory] when the
/// runner built in it is disposed.
///
/// Claiming also sweeps sibling claims a crashed run left behind. A
/// comparison runs minutes at the very worst, so a day-old claim has no
/// living owner — and the sweep needs no registry of its own, just the
/// stamp's age. Swept on claim rather than on a schedule because a schedule
/// needs a caller wired up and remembered; this one cannot be forgotten.
/// Anything under the root *without* a stamp is not a claim and
/// not this sweep's to touch.
String claimComparisonBuildDirectory(String packageRoot) {
  var root = Directory(p.join(packageRoot, comparisonBuildRoot));
  if (root.existsSync()) {
    var expiry = DateTime.now().subtract(const Duration(days: 1));
    for (var sibling in root.listSync()) {
      try {
        var stamp = File(p.join(sibling.path, _stamp));
        if (stamp.existsSync() && stamp.statSync().modified.isBefore(expiry)) {
          sibling.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // A sibling that vanished mid-sweep, or one another process is
        // deleting too. The sweep is a courtesy, not a guarantee.
      }
    }
  }
  var directory = p.url.join(comparisonBuildRoot, '$pid-${_claims++}');
  Directory(p.join(packageRoot, directory)).createSync(recursive: true);
  File(p.join(packageRoot, directory, _stamp)).writeAsStringSync('');
  return directory;
}

/// Deletes a claimed directory, and refuses anything else: only paths under
/// [comparisonBuildRoot] are this function's to remove, so a default
/// `build/flutterware` handed over by mistake is an error rather than the
/// warm lane's artifacts gone.
void releaseComparisonBuildDirectory(String packageRoot, String directory) {
  if (!p.url.isWithin(comparisonBuildRoot, directory)) {
    throw ArgumentError.value(
      directory,
      'directory',
      'not a claimed comparison build directory',
    );
  }
  try {
    Directory(p.join(packageRoot, directory)).deleteSync(recursive: true);
  } on FileSystemException {
    // A base checkout somebody disposed of first takes the claim with it.
  }
}
