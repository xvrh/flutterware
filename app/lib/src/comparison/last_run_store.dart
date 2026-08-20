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

  LastComparison? read(ComparisonHalfKind kind) {
    var file = _fileFor(kind);
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
    file.writeAsStringSync(jsonEncode(last.toJson()));
  }
}
