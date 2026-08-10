/// Whether a coding agent is working in a checkout, read from files on disk.
///
/// **All of the unstable knowledge in this repository lives here.** The session
/// format below is Claude Code's private business: it is undocumented, it will
/// change, and nothing else may depend on its shape. What leaves this file is
/// [AgentFacts], which is ours.
///
/// The contract that makes that safe: **every failure is [AgentState.none]**.
/// A format that stopped parsing, a directory that is not where we guessed, a
/// half-written line — all of them mean "no agent here", which the explorer
/// already renders as a quiet dash and the CLI already omits the column for.
/// An agent is a nice-to-have; nothing about this screen may hinge on it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../facts.dart';

/// One agent's way of leaving traces. Claude is the first; the interface exists
/// from the start because retrofitting one costs far more than declaring it.
abstract class AgentProbe {
  /// What this probe reports about the checkout at [worktreePath], or null when
  /// it has nothing to say about it.
  Future<AgentFacts?> probe(String worktreePath);
}

/// Claude Code, via `~/.claude/projects/`.
class ClaudeAgentProbe implements AgentProbe {
  ClaudeAgentProbe({
    String? projectsRoot,
    DateTime Function()? now,
    this.idleAfter = const Duration(minutes: 30),
  }) : projectsRoot = projectsRoot ?? _defaultRoot(),
       _now = now ?? DateTime.now;

  static String _defaultRoot() {
    var home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return p.join(home, '.claude', 'projects');
  }

  final String projectsRoot;
  final DateTime Function() _now;

  /// After this, a session is [AgentState.idle] whatever its last record says.
  ///
  /// It is also what bounds the damage of the one thing file-watching cannot
  /// see: an agent killed mid-turn leaves a session whose last record is a user
  /// message, which reads as `working` forever without this.
  final Duration idleAfter;

  /// How much of the session file is read.
  ///
  /// The files in a working repository run to hundreds of kilobytes — 660 KB
  /// was the largest measured — and everything this needs is appended at the
  /// end. Reading them whole, once per worktree, per refresh, would be the most
  /// expensive thing the explorer does and would buy nothing.
  static const tailBytes = 64 * 1024;

  @override
  Future<AgentFacts?> probe(String worktreePath) async {
    try {
      var directory = Directory(p.join(projectsRoot, encodePath(worktreePath)));
      if (!directory.existsSync()) {
        return const AgentFacts(state: AgentState.none);
      }

      var newest = _newestSession(directory);
      if (newest == null) return const AgentFacts(state: AgentState.none);

      return parseClaudeSession(
        await _tail(newest.file),
        modifiedAt: newest.modified,
        worktreePath: worktreePath,
        now: _now(),
        idleAfter: idleAfter,
      );
    } catch (_) {
      // Unreadable, gone between the listing and the read, or a format that
      // moved. See the contract at the top of this file.
      return const AgentFacts(state: AgentState.none);
    }
  }

  ({File file, DateTime modified})? _newestSession(Directory directory) {
    ({File file, DateTime modified})? newest;
    for (var entry in directory.listSync()) {
      if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
      var modified = entry.statSync().modified;
      if (newest == null || modified.isAfter(newest.modified)) {
        newest = (file: entry, modified: modified);
      }
    }
    return newest;
  }

  /// The last [tailBytes] of [file], with any partial first line dropped.
  static Future<String> _tail(File file) async {
    var handle = await file.open();
    try {
      var length = await handle.length();
      var from = length > tailBytes ? length - tailBytes : 0;
      await handle.setPosition(from);
      var bytes = await handle.read(length - from);
      var text = utf8.decode(bytes, allowMalformed: true);
      // Seeking to a byte offset lands mid-line and, with multi-byte
      // characters, mid-rune. Both are handled by throwing the first line away
      // whenever we did not start at the beginning of the file.
      if (from > 0) {
        var newline = text.indexOf('\n');
        text = newline < 0 ? '' : text.substring(newline + 1);
      }
      return text;
    } finally {
      await handle.close();
    }
  }
}

/// `~/.claude/projects/<the worktree path, with `/`, `\`, `_` and `.` as `-`>`.
///
/// **Derived by measurement, not from documentation.** Checked against every
/// directory on one machine (2026-08-10): of the 57 with a readable session,
/// this rule reproduces 55 exactly. Separators alone reproduce far fewer —
/// a checkout under `claude_worktrees/` lands in `claude-worktrees-…`, so
/// dropping the underscore rule silently loses every worktree on a machine
/// laid out that way.
///
/// The other two are not encoding failures: those directories hold a session
/// whose recorded `cwd` is a *different* worktree, presumably resumed or
/// copied. Which is the case [parseClaudeSession]'s `cwd` check exists for.
///
/// **Lossy, and knowingly so.** A path that really contains a dash is
/// indistinguishable from one containing a separator once encoded. Survivable
/// because of what a wrong guess costs: the directory does not exist, the probe
/// reports no agent, and the column disappears. A wrong *match* would be the
/// dangerous outcome, and the `cwd` check rules it out.
String encodePath(String worktreePath) =>
    p.canonicalize(worktreePath).replaceAll(RegExp(r'[/\\_.]'), '-');

/// Reads the tail of a session file into facts.
///
/// Pure, so the format — the part guaranteed to change — is testable from a
/// string rather than from a home directory.
///
/// Records are scanned **backwards**, because everything here is the *last* of
/// its kind: the title is re-appended on every change, and so is the last
/// prompt.
AgentFacts parseClaudeSession(
  String tail, {
  required DateTime modifiedAt,
  required String worktreePath,
  required DateTime now,
  Duration idleAfter = const Duration(minutes: 30),
}) {
  String? title;
  String? lastPrompt;
  String? model;
  String? cwd;
  String? lastMessageRole;

  var lines = tail.split('\n');
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = lines[i].trim();
    if (line.isEmpty) continue;
    Map<String, Object?> record;
    try {
      record = jsonDecode(line) as Map<String, Object?>;
    } on FormatException {
      continue;
    } on TypeError {
      continue;
    }

    cwd ??= record['cwd'] as String?;

    switch (record['type']) {
      case 'custom-title':
        title ??= record['customTitle'] as String?;
      case 'last-prompt':
        lastPrompt ??= record['lastPrompt'] as String?;
      case 'assistant':
        // The role of the newest message decides working from waiting, so only
        // the first one found scanning backwards counts. `custom-title` and
        // `last-prompt` are appended *after* it and are not messages.
        lastMessageRole ??= 'assistant';
        if (record['message'] case Map<String, Object?> message) {
          model ??= message['model'] as String?;
        }
      case 'user':
        lastMessageRole ??= 'user';
    }
  }

  // **The guard against the lossy directory name.** A session that says it is
  // for another checkout is not this checkout's session, whatever directory it
  // was found in.
  if (cwd != null && p.canonicalize(cwd) != p.canonicalize(worktreePath)) {
    return const AgentFacts(state: AgentState.none);
  }

  if (lastMessageRole == null && title == null) {
    return const AgentFacts(state: AgentState.none);
  }

  var age = now.difference(modifiedAt);
  var state = age > idleAfter
      ? AgentState.idle
      // The last word was the agent's, so the next one is yours.
      : lastMessageRole == 'assistant'
      ? AgentState.waiting
      : AgentState.working;

  return AgentFacts(
    state: state,
    title: title,
    lastPrompt: lastPrompt,
    at: modifiedAt,
    model: model,
  );
}
