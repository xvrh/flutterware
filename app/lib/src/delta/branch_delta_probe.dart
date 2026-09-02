/// Reads a [BranchDelta]: the changes screen's git probe for the delta, the
/// comparison's import graph for the reach, and the hunk bodies for the lines.
///
/// Pure Dart, and meant to run inside `Isolate.run` — see
/// [BranchDeltaController]. Measured on this repository's studio (151 entry
/// files): ~70 ms of git and ~800 ms of parsing for the graph, cold.
library;

import 'dart:io';

import 'package:flutterware/plugins.dart' show ChangesConfig;
import 'package:path/path.dart' as p;

import '../changes/changes_config_cache.dart';
import '../changes/changes_probe.dart';
import '../changes/diff_lines.dart';
import '../changes/patch_index.dart';
import '../comparison/base_ref.dart';
import '../comparison/import_graph.dart';
import '../worktrees/facts_store.dart';
import 'branch_delta.dart';

class BranchDeltaProbe {
  BranchDeltaProbe({ChangesProbe? changes, GitRunner? runGit})
    : _changes = changes ?? ChangesProbe(runGit: runGit);

  final ChangesProbe _changes;

  /// The delta of [worktreePath], with reach computed for [files]
  /// (worktree-relative).
  ///
  /// [packageConfigs] are candidate `package_config.json` paths, first
  /// existing one wins — the checkout's own for a workspace, a package's for
  /// a lone one. None readable degrades to relative imports only, the way
  /// [ImportGraph.read] documents.
  Future<BranchDelta> probe(
    String worktreePath, {
    Set<String> files = const {},
    List<String> packageConfigs = const [],
    BranchDelta? previous,
  }) async {
    var set = await _changes.probe(
      worktreePath,
      config: await _configFor(worktreePath),
    );
    var readAt = DateTime.now();
    if (set.mergeBase == null) {
      return BranchDelta.none(worktreePath: worktreePath, readAt: readAt);
    }

    var changed = <String, DeltaFile>{};
    for (var file in set.changed) {
      var edits = _editsOf(set.patch, file);
      changed[file.path] = DeltaFile(
        path: file.path,
        status: file.status,
        oldPath: file.oldPath,
        added: edits.added,
        removedAt: edits.removedAt,
        uncommitted: set.uncommitted.contains(file.path),
      );
    }
    var untracked = <String>{};
    var untrackedDirectories = <String>{};
    for (var entry in set.untracked) {
      if (entry.isDirectory) {
        untrackedDirectories.add(entry.path);
      } else {
        untracked.add(entry.path);
      }
    }
    var delta = BranchDelta(
      worktreePath: worktreePath,
      base: set.base,
      mergeBase: set.mergeBase,
      head: set.head,
      readAt: readAt,
      files: changed,
      untracked: untracked,
      untrackedDirectories: untrackedDirectories,
    );
    if (files.isEmpty || delta.isEmpty) return delta;

    // The graph is the expensive half, and its answer only moves when the
    // delta or the files asked about do. An idle checkout re-read on a tick
    // gets its reach back for free.
    if (previous != null &&
        previous.sameChangesAs(delta) &&
        previous.reachedFiles.length == files.length &&
        files.every(previous.reach.containsKey)) {
      return delta.withReach(previous.reach);
    }

    var config = packageConfigs
        .where((path) => File(path).existsSync())
        .firstOrNull;
    var graph = ImportGraph.read(root: worktreePath, packageConfig: config);
    // Each closure is tested against the same few hundred changed paths, so
    // the per-file verdict is remembered across entries.
    var verdicts = <String, String?>{};
    var reach = <String, List<String>>{};
    for (var file in files) {
      var hits = <String>[];
      for (var dep in graph.closureOf(
        p.joinAll([worktreePath, ...file.split('/')]),
      )) {
        var hit = verdicts.putIfAbsent(dep, () {
          var path = p.split(dep).join('/');
          if (isGenerated(path)) return null;
          return changed.containsKey(path) || delta.isUntracked(path)
              ? path
              : null;
        });
        if (hit != null && hit != file) hits.add(hit);
      }
      reach[file] = hits;
    }
    return delta.withReach(reach);
  }

  /// A regenerated file is a real change to a closure and rarely an
  /// interesting one, so it counts as an edit to its own entries and not as
  /// reach.
  static bool isGenerated(String path) =>
      path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

  /// The project's `base:` override, remembered under the main checkout the
  /// way the changes screen remembers it. Unreadable is the same as absent.
  ///
  /// The main checkout comes from `BaseRef.repositoryOf`, which is the one
  /// git spawn here not made by the changes probe — through `runGit`, like
  /// every other, so an inherited `GIT_DIR` cannot point it elsewhere.
  Future<ChangesConfig?> _configFor(String worktreePath) async {
    try {
      var repoRoot = await BaseRef.repositoryOf(worktreePath);
      return resolveChangesConfig(
        worktreePath,
        WorktreeFactsStore.open(repoRoot),
      ).config;
    } on Object {
      return null;
    }
  }

  /// The runs of new lines and the positions of removed ones, read off the
  /// hunk bodies through the changes screen's own line parser.
  static ({List<LineRange> added, List<int> removedAt}) _editsOf(
    PatchIndex patch,
    FileChange file,
  ) {
    var added = <LineRange>[];
    var removedAt = <int>[];
    for (var hunk in file.hunks) {
      // The new-side line before the point being read, which is where a
      // removal is recorded.
      var before = hunk.newStart - 1;
      int? runStart;
      for (var line in parseHunkLines(patch.textForHunk(hunk), hunk)) {
        switch (line.kind) {
          case DiffLineKind.added:
            runStart ??= line.newNumber;
            before = line.newNumber!;
          case DiffLineKind.removed:
            if (runStart case var start?) {
              added.add(LineRange(start, before));
              runStart = null;
            }
            if (removedAt.isEmpty || removedAt.last != before) {
              removedAt.add(before);
            }
          case DiffLineKind.context:
            if (runStart case var start?) {
              added.add(LineRange(start, before));
              runStart = null;
            }
            before = line.newNumber!;
          case DiffLineKind.meta:
            break;
        }
      }
      if (runStart case var start?) added.add(LineRange(start, before));
    }
    return (added: added, removedAt: removedAt);
  }
}
