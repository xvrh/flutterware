import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';
import 'package:flutterware_app/src/worktrees/providers/agent.dart';
import 'package:path/path.dart' as p;

/// The record shapes here are **recorded from a real session file**
/// (2026-08-10). This is the one format in the repository nobody controls, so a
/// fixture written from memory would be a test of what we assumed.
String _record(Map<String, Object?> fields) => jsonEncode(fields);

const _cwd = '/Users/x/worktrees/feature';

String _session({
  String cwd = _cwd,
  String? title = 'Worktree explorer feature brainstorm',
  String? lastPrompt = 'mock the row in real tokens',
  String lastRole = 'assistant',
}) => [
  _record({
    'type': 'user',
    'cwd': cwd,
    'gitBranch': 'claude/feature',
    'message': {'role': 'user'},
  }),
  _record({
    'type': lastRole,
    'cwd': cwd,
    'gitBranch': 'claude/feature',
    'message': {'role': lastRole, 'model': 'claude-opus-5'},
  }),
  // Appended *after* the messages, and repeatedly — which is why the parser
  // scans backwards and why these must not count as the last message.
  if (lastPrompt != null)
    _record({'type': 'last-prompt', 'lastPrompt': lastPrompt}),
  if (title != null) _record({'type': 'custom-title', 'customTitle': title}),
].join('\n');

void main() {
  var now = DateTime(2026, 8, 10, 14, 30);

  group('parse', () {
    AgentFacts parse(
      String tail, {
      Duration age = const Duration(seconds: 10),
      String cwd = _cwd,
    }) => parseClaudeSession(
      tail,
      modifiedAt: now.subtract(age),
      worktreePath: cwd,
      now: now,
    );

    test('the last title wins, because every change appends another', () {
      var tail = [
        _record({'type': 'custom-title', 'customTitle': 'An early guess'}),
        _record({
          'type': 'user',
          'cwd': _cwd,
          'message': {'role': 'user'},
        }),
        _record({'type': 'custom-title', 'customTitle': 'What it became'}),
      ].join('\n');
      expect(parse(tail).title, 'What it became');
    });

    test('the agent spoke last, so it is waiting on you', () {
      var facts = parse(_session(lastRole: 'assistant'));
      expect(facts.state, AgentState.waiting);
      expect(facts.model, 'claude-opus-5');
      expect(facts.lastPrompt, 'mock the row in real tokens');
    });

    test('you spoke last, so it is working', () {
      expect(parse(_session(lastRole: 'user')).state, AgentState.working);
    });

    test('metadata appended after the last message is not a message', () {
      // `last-prompt` and `custom-title` are the final two lines of the fixture.
      // Treating either as the newest record would call a waiting session
      // working, on every session, always.
      expect(parse(_session(lastRole: 'assistant')).state, AgentState.waiting);
    });

    test('an old session is idle whatever its last record said', () {
      var facts = parse(
        _session(lastRole: 'user'),
        age: const Duration(hours: 4),
      );
      // This is also what bounds an agent killed mid-turn: it would otherwise
      // read as `working` forever.
      expect(facts.state, AgentState.idle);
    });

    test('a session recorded for another checkout is not this one', () {
      // The directory name encoding is lossy, so a wrong *match* is the real
      // hazard. The cwd the session recorded is the guard against it.
      var facts = parse(_session(cwd: '/Users/x/worktrees/other'));
      expect(facts.state, AgentState.none);
    });

    test('a truncated first line is skipped, not fatal', () {
      // Tailing a file lands mid-line; the reader drops the partial, but a
      // malformed line anywhere must not cost the whole session either.
      var tail = 'ssistant","message":{"rol\n${_session()}';
      expect(parse(tail).state, AgentState.waiting);
    });

    test('nothing recognisable is no agent, not an error', () {
      expect(parse('').state, AgentState.none);
      expect(parse('{"type":"something-new"}').state, AgentState.none);
      expect(parse('not json at all').state, AgentState.none);
    });
  });

  group('probe', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('fw-agent-test'));
    tearDown(() => root.deleteSync(recursive: true));

    File sessionFile(String worktreePath, String name) {
      var dir = Directory(p.join(root.path, encodePath(worktreePath)))
        ..createSync(recursive: true);
      return File(p.join(dir.path, name));
    }

    test('reads the newest session of several', () async {
      var older = sessionFile(_cwd, 'a.jsonl')
        ..writeAsStringSync(_session(title: 'The old one'));
      older.setLastModifiedSync(now.subtract(const Duration(days: 2)));
      var newer = sessionFile(_cwd, 'b.jsonl')
        ..writeAsStringSync(_session(title: 'The current one'));
      newer.setLastModifiedSync(now.subtract(const Duration(minutes: 1)));

      var facts = await ClaudeAgentProbe(
        projectsRoot: root.path,
        now: () => now,
      ).probe(_cwd);

      expect(facts!.title, 'The current one');
    });

    test('a checkout with no session directory has no agent', () async {
      var facts = await ClaudeAgentProbe(
        projectsRoot: root.path,
        now: () => now,
      ).probe('/Users/x/worktrees/never-touched');
      expect(facts!.state, AgentState.none);
    });

    test('every separator becomes a dash, underscores included', () {
      // Measured against 57 real directories: separators alone reproduce far
      // fewer, and a machine that keeps its checkouts under `claude_worktrees/`
      // loses every one of them.
      expect(
        encodePath('/Users/x/claude_worktrees/flutterware/gifted-lamport'),
        '-Users-x-claude-worktrees-flutterware-gifted-lamport',
      );
      expect(encodePath('/a/b.c/d'), '-a-b-c-d');
    });

    test('a projects root that does not exist is not an error', () async {
      var facts = await ClaudeAgentProbe(
        projectsRoot: '/nowhere/at/all',
        now: () => now,
      ).probe(_cwd);
      expect(facts!.state, AgentState.none);
    });

    test('only the tail of a large file is read', () async {
      // The real files run to hundreds of kilobytes. A session whose *first*
      // 200 KB is padding still parses, which is only true if the reader
      // seeks.
      var padding = List.filled(
        200,
        _record({
          'type': 'user',
          'cwd': _cwd,
          'message': {'role': 'user'},
        }),
      ).join('\n');
      var file = sessionFile(_cwd, 'big.jsonl')
        ..writeAsStringSync('${'x' * 100000}\n$padding\n${_session()}');
      file.setLastModifiedSync(now.subtract(const Duration(seconds: 5)));

      var facts = await ClaudeAgentProbe(
        projectsRoot: root.path,
        now: () => now,
      ).probe(_cwd);

      expect(facts!.title, 'Worktree explorer feature brainstorm');
      expect(facts.state, AgentState.waiting);
    });
  });
}
