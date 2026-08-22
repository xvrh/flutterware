import 'dart:io';

import 'package:path/path.dart' as p;

/// Where a package's scenario runs land when the caller named no output.
String scenarioRunsDirIn(String packageRoot) =>
    p.join(packageRoot, 'build', 'flutterware', 'scenario_runs');

/// A run directory names itself with `DateTime.now().millisecondsSinceEpoch`,
/// and a panel session prefixes that. Ten digits rather than thirteen so the
/// match is about the shape and not about what year it is.
final _stamped = RegExp(r'^\d{10,}$');
final _panelStamped = RegExp(r'^panel-\d{10,}$');

/// Deletes all but the newest [keep] run directories of each series under
/// [packageRoot], and answers how many it removed.
///
/// Nothing swept these, ever. A run writes a directory per invocation and the
/// panel writes one per session, and a recorded panel run is *large* — 512MB
/// measured on the example suite, because a recording is hundreds of frames of
/// raw rgba and raw is the right answer for a 30fps player. Left alone, one
/// worktree here reached 848MB across 37 directories. This is the cheap end of
/// that problem: the pictures are worth what they cost while anybody is
/// looking at them, and worth nothing the moment the next run replaces them.
///
/// **Two series, kept apart.** A panel session captures one scenario and
/// writes no report; a run writes `run.json`. Drift walks back from the newest
/// stamped directory looking for the previous report and skips `panel-*`
/// entirely, so a panel run must never be able to age out the report drift is
/// about to read. Keeping [keep] of each is also why the default is three and
/// not two: drift keeps walking when a directory holds no report, and a margin
/// costs one directory where getting it wrong costs the drift.
///
/// **Only what a run named itself.** A caller that passed `--output` owns that
/// directory — it may be a CI artifact path, and it may sit right here — so
/// only the millisecond-stamped names above are ever candidates. Anything else
/// under this directory is left exactly where it is.
///
/// [protect] names directories this sweep may not touch, and they are kept
/// *in addition* to [keep] rather than counted against it — a protected
/// directory is one somebody is reading right now, and letting it push a
/// newer one out would be the wrong way round. The panel names every run it
/// still has a page for; a run names the output it just wrote, because
/// `--output` may point at a path that looks exactly like a stamped one and
/// the order here is the *name* rather than the mtime.
///
/// A protected path protects **the directory that holds it** too, not only an
/// exact match. A matrix run writes a directory per point *inside* the
/// stamped one and reports those subdirectories as its outputs, so naming
/// what a run wrote would otherwise leave the stamped parent — the thing this
/// sweep actually deletes, `index.json` and all — unnamed and fair game.
///
/// Every failure is swallowed per directory. This is housekeeping: another
/// process winning a race to delete the same run is the expected case, and a
/// sweep is never worth failing a run over.
int sweepScenarioRuns(
  String packageRoot, {
  int keep = 3,
  Set<String> protect = const {},
}) {
  var runs = Directory(scenarioRunsDirIn(packageRoot));
  List<FileSystemEntity> entries;
  try {
    entries = runs.listSync();
  } on FileSystemException {
    return 0;
  }

  var kept = [for (var path in protect) p.canonicalize(path)];
  bool isProtected(String directory) {
    var canonical = p.canonicalize(directory);
    for (var path in kept) {
      if (path == canonical || p.isWithin(canonical, path)) return true;
    }
    return false;
  }

  var stamped = <Directory>[];
  var panels = <Directory>[];
  for (var entity in entries) {
    if (entity is! Directory) continue;
    if (isProtected(entity.path)) continue;
    var name = p.basename(entity.path);
    if (_stamped.hasMatch(name)) {
      stamped.add(entity);
    } else if (_panelStamped.hasMatch(name)) {
      panels.add(entity);
    }
  }

  var deleted = 0;
  for (var series in [stamped, panels]) {
    // By the stamp as a number, not as a string: the names are the same length
    // today and will not be forever, and a sweep that got the order wrong
    // would delete the newest run rather than the oldest.
    series.sort((a, b) => _stampOf(a).compareTo(_stampOf(b)));
    var stale = series.length - keep;
    if (stale <= 0) continue;
    for (var old in series.take(stale)) {
      try {
        old.deleteSync(recursive: true);
        deleted++;
      } on FileSystemException {
        // Gone already, or held open by whoever is reading it. Either way the
        // next sweep gets it.
      }
    }
  }
  return deleted;
}

int _stampOf(Directory directory) {
  var name = p.basename(directory.path);
  var digits = name.startsWith('panel-') ? name.substring(6) : name;
  return int.tryParse(digits) ?? 0;
}
