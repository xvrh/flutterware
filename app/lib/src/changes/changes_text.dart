/// A [ChangeSet], rendered as text.
///
/// The second renderer of one model — this and `--json` — with the GUI's screen
/// to come. It lives here rather than in `cli.dart` so it can be tested without
/// a CLI, exactly as `facts_text.dart` is.
library;

import 'change_set.dart';
import 'changes_config_cache.dart';
import 'patch_index.dart';
import 'ranking.dart';

/// The whole report, as lines.
///
/// **Widths come from the content**, like the worktree table: a path is what you
/// would copy out of this and hand to `git`, so it is never truncated, and
/// sizing to the longest one is what keeps the columns lined up anyway.
List<String> changesReport(ChangeSet set) {
  var lines = <String>[_headline(set)];

  if (set.refusal case var why?) {
    lines
      ..add('')
      ..add('  $why');
  }

  if (set.baseSource == BaseSource.none) {
    lines
      ..add('')
      ..add(
        '  No base branch: none of origin/HEAD, main or master resolved here.',
      )
      ..add(
        '  Showing uncommitted work only. Name one with '
        'ChangesConfig(base: …) in tool/flutterware.dart.',
      );
  }

  if (ResolvedChangesConfig(null, set.configState).notice case var why?) {
    lines
      ..add('')
      ..add('  $why');
  }

  // Widths come from **every** file, not from each section, so the columns of
  // "look here first" and the ones below it line up as one table.
  var all = set.ranked;
  if (all.isNotEmpty) {
    var pathWidth = all
        .map((f) => _pathOf(f).length)
        .fold(0, (a, b) => a > b ? a : b);
    var addWidth = all
        .map((f) => '+${f.added}'.length)
        .fold(0, (a, b) => a > b ? a : b);
    var removeWidth = all
        .map((f) => '-${f.removed}'.length)
        .fold(0, (a, b) => a > b ? a : b);

    void section(String? heading, List<RankedFile> files) {
      if (files.isEmpty) return;
      lines.add('');
      if (heading != null) lines.add('  $heading');
      for (var ranked in files) {
        var file = ranked.file;
        var notes = [?ranked.reason, ..._notesFor(file, set)];
        lines.add(
          '  ${_letter(file.status)}  '
          '${_pathOf(file).padRight(pathWidth)}  '
          '${'+${file.added}'.padLeft(addWidth)} '
          '${'-${file.removed}'.padLeft(removeWidth)}'
          '${notes.isEmpty ? '' : '  ${notes.join(' · ')}'}',
        );
      }
    }

    var attention = set.ordered(RankTier.attention);
    var noise = set.ordered(RankTier.noise);
    // Headings only when there is something to tell apart — one flat list is
    // what an unranked branch should read as.
    var sectioned = attention.isNotEmpty || noise.isNotEmpty;

    section(sectioned ? 'look here first' : null, attention);
    section(
      sectioned && attention.isNotEmpty ? 'changes' : null,
      set.ordered(RankTier.ordinary),
    );
    // **Listed, never summarised away.** `fw changes` is what an agent reads,
    // and a drawer it cannot click is a drawer that hides things from it.
    section('low signal', noise);
  }

  // Pinned first, in their own section, exactly as the screen draws them: a
  // new file an agent has not staged is what an attention rule is for.
  var pinned = [
    for (var entry in set.untracked)
      if (entry.isPinned) entry,
  ];
  var rest = [
    for (var entry in set.untracked)
      if (!entry.isPinned) entry,
  ];

  void untracked(String heading, List<UntrackedEntry> entries) {
    if (entries.isEmpty) return;
    lines
      ..add('')
      ..add('  $heading');
    for (var entry in entries) {
      lines.add(
        '  ?  ${entry.path}'
        '${entry.reason == null ? '' : '   ${entry.reason}, not tracked yet'}'
        '${entry.isDirectory ? '   directory, not scanned' : ''}',
      );
    }
  }

  untracked('look here first, not tracked yet', pinned);
  untracked('untracked', rest);

  if (set.isEmpty) {
    lines
      ..add('')
      ..add('  Nothing to show.');
  }

  return lines;
}

String _headline(ChangeSet set) {
  var parts = <String>[
    '${set.changed.length} ${set.changed.length == 1 ? 'file' : 'files'}',
    '+${set.added} -${set.removed}',
  ];
  var uncommitted = set.changed
      .where((f) => set.uncommitted.contains(f.path))
      .length;
  if (uncommitted > 0) parts.add('$uncommitted uncommitted');
  if (set.untracked.isNotEmpty) {
    parts.add('${set.untracked.length} untracked');
  }
  parts.add(switch (set.baseSource) {
    BaseSource.none => 'no base',
    BaseSource.configured => 'base ${set.base} (configured)',
    BaseSource.inferred => 'base ${set.base} (inferred)',
  });
  return parts.join('  ·  ');
}

/// A rename says where it came from, because that is the whole information in
/// it — `R` alone is a status nobody can act on.
String _pathOf(FileChange file) =>
    file.oldPath == null ? file.path : '${file.path} <- ${file.oldPath}';

List<String> _notesFor(FileChange file, ChangeSet set) => [
  if (set.uncommitted.contains(file.path)) 'uncommitted',
  if (file.isBinary) 'binary',
  if (file.hunks.length == 1)
    '1 hunk'
  else if (file.hunks.length > 1)
    '${file.hunks.length} hunks',
  if (file.patchBytes > ChangesLimits.filePatchBytes) 'too large to expand',
];

String _letter(ChangeStatus status) => switch (status) {
  ChangeStatus.added => 'A',
  ChangeStatus.modified => 'M',
  ChangeStatus.deleted => 'D',
  ChangeStatus.renamed => 'R',
};
