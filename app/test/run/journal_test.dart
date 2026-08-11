import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/journal.dart';

/// The run journal: an append-only story two processes write to, with a
/// stated cap.
void main() {
  late Directory runDir;
  late RunHandle handle;

  setUp(() {
    runDir = Directory.systemTemp.createTempSync('fw-journal-');
    handle = RunHandle(
      worktree: '/w',
      worktreeName: '~',
      device: 'macos',
      entrypoint: 'lib/main.dart',
      launcherPid: pid,
      startedAt: DateTime.now(),
    ).publish(runDir.path);
  });

  tearDown(() => runDir.deleteSync(recursive: true));

  test('appends and reads back in order', () {
    appendJournal(
      handle,
      JournalEntry(at: 't1', verb: 'tap', actor: 'agent', target: '"Pay"'),
    );
    appendJournal(
      handle,
      JournalEntry(at: 't2', verb: 'reload', elapsedMs: 90),
    );

    var entries = readJournal(handle);
    expect([for (var e in entries) e.verb], ['tap', 'reload']);
    expect(entries.first.target, '"Pay"');
    expect(entries.last.elapsedMs, 90);
  });

  test('tail takes the recent end', () {
    for (var i = 0; i < 5; i++) {
      appendJournal(handle, JournalEntry(at: 't$i', verb: 'v$i'));
    }
    expect([for (var e in readJournal(handle, tail: 2)) e.verb], ['v3', 'v4']);
  });

  test('a torn line is skipped, not fatal', () {
    appendJournal(handle, JournalEntry(at: 't1', verb: 'tap'));
    File(
      journalPathFor(handle)!,
    ).writeAsStringSync('{"broken', mode: FileMode.append);

    expect(readJournal(handle).single.verb, 'tap');
  });

  test('a journal past the cap rotates once, with a marker', () {
    var path = journalPathFor(handle)!;
    var line = '${jsonEncode(JournalEntry(at: 'old', verb: 'tap').toJson())}\n';
    File(path).writeAsStringSync(line * (journalMaxBytes ~/ line.length + 2));

    appendJournal(handle, JournalEntry(at: 'new', verb: 'observe'));

    expect(File('$path.1').existsSync(), isTrue);
    var entries = readJournal(handle);
    expect(entries.first.rotated, isTrue);
    expect(entries.last.verb, 'observe');
  });

  test('an unpublished handle journals nowhere, quietly', () {
    var loose = RunHandle(
      worktree: '/w',
      worktreeName: '~',
      device: 'macos',
      entrypoint: 'lib/main.dart',
      launcherPid: pid,
      startedAt: DateTime.now(),
    );
    appendJournal(loose, JournalEntry(at: 't', verb: 'tap'));
    expect(readJournal(loose), isEmpty);
  });
}
