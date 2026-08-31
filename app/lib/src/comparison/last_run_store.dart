import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'comparison_controller.dart';
import 'last_run.dart';

/// The last finished run of each half, on disk beside the worktree's other
/// comparison artifacts (see `comparisonDirFor`).
///
/// One file per half rather than one for both, because the halves run
/// independently now: comparing the previews must not stamp a new time on a
/// scenario result it did not touch.
class LastRunStore {
  const LastRunStore(this.directory);

  final String directory;

  File _fileFor(ComparisonHalfKind kind) =>
      File(p.join(directory, 'last-${kind.name}.json'));

  /// The run before the last one — what *new since you last looked* is
  /// measured against.
  ///
  /// One generation, because that is the whole question. Four entries that
  /// report changed on every comparison teach a reader to skim past the list,
  /// and the fix is not a history: it is being able to say which of today's
  /// findings were not in yesterday's.
  File _previousFileFor(ComparisonHalfKind kind) =>
      File(p.join(directory, 'previous-${kind.name}.json'));

  LastComparison? read(ComparisonHalfKind kind) => _readFile(_fileFor(kind));

  /// The run before [read]'s, or null on the first ever comparison.
  LastComparison? readPrevious(ComparisonHalfKind kind) =>
      _readFile(_previousFileFor(kind));

  LastComparison? _readFile(File file) {
    try {
      if (!file.existsSync()) return null;
      var json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      return LastComparison.fromJson(json.cast<String, Object?>());
    } on Object {
      // A truncated or hand-edited file is not worth an error state — the
      // panel simply has no last run to show.
      return null;
    }
  }

  void write(ComparisonHalfKind kind, LastComparison last) {
    var file = _fileFor(kind);
    file.parent.createSync(recursive: true);
    // The outgoing run becomes the previous one. Copied rather than renamed:
    // a rename that fails half way would leave no last run at all, where a
    // failed copy leaves both files exactly as they were.
    if (file.existsSync()) {
      try {
        file.copySync(_previousFileFor(kind).path);
      } on Object {
        // A cache that cannot keep one generation of history still compares.
      }
    }
    file.writeAsStringSync(jsonEncode(last.toJson()));
  }
}
