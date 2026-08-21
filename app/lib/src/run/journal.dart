import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'handle.dart';

/// The story of a run: every tool step appended to one file beside the
/// handle, in the run dir — same files-not-memory rule, same payoff. The GUI
/// renders it as a step strip, an agent reads it to remember what its own
/// previous hops did (a CLI invocation is a fresh process), and a human
/// reviews what the AI clicked while they were not looking.
///
/// Tool steps — acts, reloads, restarts — plus the human's taps between
/// them: the guest records pointer-ups (`HumanActions`), they ride the next
/// act reply as a since-last-step delta, and land here as `actor: human`
/// entries ahead of the step that carried them. No screenshot on those; the
/// step that follows photographs the screen they produced.
class JournalEntry {
  JournalEntry({
    required this.at,
    required this.verb,
    this.actor,
    this.target,
    this.error,
    this.failure,
    this.attempts,
    this.elapsedMs,
    this.settled,
    this.settleMs,
    this.lifecycle,
    this.capture,
    this.reported,
    this.screenshot,
    this.tree,
    this.texts,
    this.semantics,
    this.logLines,
    this.errorCount,
    this.layer,
    this.reconciled,
    this.rotated = false,
  });

  factory JournalEntry.fromJson(Map<String, Object?> json) => JournalEntry(
    at: json['at'] as String? ?? '',
    verb: json['verb'] as String? ?? '',
    actor: json['actor'] as String?,
    target: json['target'] as String?,
    error: json['error'] as String?,
    failure: json['failure'] as String?,
    attempts: json['attempts'] as int?,
    elapsedMs: json['elapsedMs'] as int?,
    settled: json['settled'] as bool?,
    settleMs: json['settleMs'] as int?,
    lifecycle: json['lifecycle'] as String?,
    capture: json['capture'] as String?,
    reported: switch (json['reported']) {
      List reported => [for (var what in reported) '$what'],
      _ => null,
    },
    screenshot: json['screenshot'] as String?,
    tree: json['tree'] as String?,
    texts: json['texts'] as String?,
    semantics: json['semantics'] as String?,
    logLines: json['logLines'] as int?,
    errorCount: json['errorCount'] as int?,
    layer: json['layer'] as String?,
    reconciled: json['reconciled'] as int?,
    rotated: json['rotated'] as bool? ?? false,
  );

  /// ISO-8601, UTC. Entries order by file position; this is for reading.
  final String at;

  /// A drive verb, or `reload` / `restart` / `stop` / `launch`.
  final String verb;

  /// Who acted — `agent`, `human`, or absent when the surface did not say.
  final String? actor;

  final String? target;

  /// The refusal, when the verb was refused. A journal that only kept
  /// successes would read as a cleaner session than anyone had.
  final String? error;

  final String? failure;
  final int? attempts;
  final int? elapsedMs;
  final bool? settled;
  final int? settleMs;
  final String? lifecycle;

  /// The `fw://` address of this step's capture — what to hand back to ask a
  /// different question about this moment.
  ///
  /// The manifest beside it (`<stamp>.capture.json`) lists the four legs and
  /// what is in each.
  final String? capture;

  /// What this step actually handed back — `screen`, `tree`, `screenshot`,
  /// `find`, `at`, `styles`.
  ///
  /// This is where the scoping lives, and the reason the artifacts no longer
  /// carry it. A journal is testimony: it has to say what the step reported,
  /// or a reviewer reads a complete tree beside a step that returned two
  /// levels of one subtree and concludes the agent saw more than it did. The
  /// files beside it are the archive and hold the whole screen. One file
  /// cannot be both, and when it tried, the archive lost — measured, 17 steps
  /// had left 5 screenshots.
  final List<String>? reported;

  /// Absolute path of the step's screenshot. Always taken; see [reported] for
  /// whether the step *returned* it.
  final String? screenshot;

  /// The step's widget tree, written beside the screenshot — persisted even
  /// when the caller did not ask for it inline, so a later reviewer has the
  /// same three legs a scenario step has.
  final String? tree;

  /// The step's visible-text projection, as a JSON list beside the tree.
  final String? texts;

  /// The semantics tree as the app published it, beside the rest.
  final String? semantics;

  /// How many log lines the step produced. The lines themselves ride the act
  /// result; the journal keeps the count.
  final int? logLines;

  final int? errorCount;

  /// Which tree the step addressed: absent or `flutter` for the drive layer,
  /// `native` for a step taken through the platform's own accessibility tree.
  /// A reviewer reading the strip should be able to see that the agent went
  /// below the widget tree — that is usually the interesting part of the
  /// story, not a footnote.
  final String? layer;

  /// How many human entries this step absorbed as its own echo.
  ///
  /// A native tap arrives at the guest as ordinary platform input, so the
  /// app's human-action recorder reports the agent's own tap back as a
  /// human's. The host drops those (see `RunCore`), and states the count
  /// rather than hiding the correction — the stated-caps rule, applied to a
  /// subtraction.
  final int? reconciled;

  /// A marker entry: the file was rotated here (see [appendJournal]).
  final bool rotated;

  Map<String, Object?> toJson() => {
    'at': at,
    'verb': verb,
    if (actor != null) 'actor': actor,
    if (target != null) 'target': target,
    if (error != null) 'error': error,
    if (failure != null) 'failure': failure,
    if (attempts != null) 'attempts': attempts,
    if (elapsedMs != null) 'elapsedMs': elapsedMs,
    if (settled != null) 'settled': settled,
    if (settleMs != null) 'settleMs': settleMs,
    if (lifecycle != null) 'lifecycle': lifecycle,
    if (capture != null) 'capture': capture,
    if (reported != null) 'reported': reported,
    if (screenshot != null) 'screenshot': screenshot,
    if (tree != null) 'tree': tree,
    if (texts != null) 'texts': texts,
    if (semantics != null) 'semantics': semantics,
    if (logLines != null) 'logLines': logLines,
    if (errorCount != null) 'errorCount': errorCount,
    if (layer != null) 'layer': layer,
    if (reconciled != null) 'reconciled': reconciled,
    if (rotated) 'rotated': true,
  };
}

/// `app-<key>.journal.jsonl`, beside the handle. Null for a handle that was
/// never published — there is no run dir to write into.
String? journalPathFor(RunHandle handle) {
  var handlePath = handle.handlePath;
  if (handlePath == null) return null;
  return '${p.withoutExtension(handlePath)}.journal.jsonl';
}

/// Where a step's artifacts (screenshots) land: `journal/app-<key>/` in the
/// run dir. Beside the handle's naming scheme, not a new one.
String? journalArtifactsDirFor(RunHandle handle) {
  var handlePath = handle.handlePath;
  if (handlePath == null) return null;
  return p.join(
    p.dirname(handlePath),
    'journal',
    p.basenameWithoutExtension(handlePath),
  );
}

/// The cap, stated rather than discovered: a journal past this rotates once —
/// the previous file becomes `.1`, replacing any older `.1` — so a long
/// session keeps its recent story and a runaway loop cannot fill the disk.
const journalMaxBytes = 5 << 20;

/// Appends one entry. JSON-lines because two processes append to the same
/// story — a GUI and an `fw` are both actors — and appending a line is the
/// one write that composes.
void appendJournal(RunHandle handle, JournalEntry entry) {
  var path = journalPathFor(handle);
  if (path == null) return;
  var file = File(path);
  if (file.existsSync() && file.lengthSync() > journalMaxBytes) {
    // Best-effort, like the torn-line tolerance above: two writers can cross
    // the cap together, and the loser of the rename race must append its
    // entry to the freshly rotated file, not fail the caller's action over
    // housekeeping.
    try {
      var previous = File('$path.1');
      if (previous.existsSync()) previous.deleteSync();
      file.renameSync(previous.path);
      File(path).writeAsStringSync(
        '${jsonEncode(JournalEntry(at: entry.at, verb: 'rotated', rotated: true).toJson())}\n',
      );
    } on FileSystemException {
      // The other writer rotated first; the append below lands either way.
    }
  }
  File(
    path,
  ).writeAsStringSync('${jsonEncode(entry.toJson())}\n', mode: FileMode.append);
}

/// The entries, oldest first. A malformed line — a torn concurrent write — is
/// skipped rather than fatal: the journal is a narrative, not a ledger.
List<JournalEntry> readJournal(RunHandle handle, {int? tail}) {
  var path = journalPathFor(handle);
  if (path == null) return const [];
  var file = File(path);
  if (!file.existsSync()) return const [];
  var entries = <JournalEntry>[];
  for (var line in file.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    try {
      entries.add(
        JournalEntry.fromJson(jsonDecode(line) as Map<String, Object?>),
      );
    } on Object {
      continue;
    }
  }
  if (tail != null && entries.length > tail) {
    return entries.sublist(entries.length - tail);
  }
  return entries;
}
