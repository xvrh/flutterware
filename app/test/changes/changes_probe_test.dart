import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/changes/change_set.dart';
import 'package:flutterware_app/src/changes/changes_probe.dart';
import 'package:flutterware_app/src/changes/patch_index.dart';

/// The parsers and the sequencing, with no repository and no git — the same
/// posture `GitProbe` and `WorktreeDiscovery` take, and for the same reason.
void main() {
  group('untracked, porcelain=v2 -z', () {
    test('a directory is one entry, and says so', () {
      // This is the branch-switch trap: a package built on another branch,
      // whose .gitignore left with the branch. git reports the topmost
      // untracked directory and does not descend, and neither do we — 1 entry
      // where -uall would give 30,000.
      var entries = parseUntrackedV2Z([
        '? packages/newpkg/build/',
        '? lib/new.dart',
      ]);

      expect(entries, hasLength(2));
      expect(entries[0].path, 'packages/newpkg/build/');
      expect(entries[0].isDirectory, isTrue);
      expect(entries[1].path, 'lib/new.dart');
      expect(entries[1].isDirectory, isFalse);
    });

    test("a rename's trailing path record is not read as an entry", () {
      // A `2 ` record carries its original path in the *next* record. A naive
      // filter would read a file called `? something` as untracked.
      var entries = parseUntrackedV2Z([
        '1 .M N... 100644 100644 100644 aaa bbb lib/a.dart',
        '2 R. N... 100644 100644 100644 ccc ddd R100 lib/new.dart',
        '? not-untracked-just-a-rename-source.dart',
        '? real.dart',
      ]);

      expect(entries.map((e) => e.path), ['real.dart']);
    });

    test('no untracked files is an empty list, not a failure', () {
      expect(parseUntrackedV2Z(['1 .M N... 1 1 1 a b lib/a.dart']), isEmpty);
      expect(parseUntrackedV2Z([]), isEmpty);
    });
  });

  group('numstat -z, the refused-patch fallback', () {
    Uint8List records(List<String> parts) =>
        Uint8List.fromList(utf8.encode(parts.join('\u0000')));

    test('reads counts and paths', () {
      var files = parseNumstatZ(
        records(['12\t3\tlib/a.dart', '0\t8\tlib/b.dart', '']),
      );
      expect(files, hasLength(2));
      expect(files[0].path, 'lib/a.dart');
      expect(files[0].added, 12);
      expect(files[0].removed, 3);
      expect(files[1].removed, 8);
    });

    test('a rename spends two extra records on its two paths', () {
      var files = parseNumstatZ(
        records([
          '4\t2\t',
          'lib/old.dart',
          'lib/new.dart',
          '1\t1\tlib/c.dart',
          '',
        ]),
      );
      expect(files, hasLength(2));
      expect(files[0].status, ChangeStatus.renamed);
      expect(files[0].oldPath, 'lib/old.dart');
      expect(files[0].path, 'lib/new.dart');
      expect(files[1].path, 'lib/c.dart', reason: 'the cursor stayed aligned');
    });

    test('a binary file counts as a file and contributes no lines', () {
      var files = parseNumstatZ(records(['-\t-\tassets/logo.png', '']));
      expect(files.single.isBinary, isTrue);
      expect(files.single.added, 0);
      expect(files.single.removed, 0);
    });
  });

  group('rename source, name-status -z', () {
    test('finds the other end of a rename', () {
      // Without it, `--file lib/new.dart` asks git for one path, git cannot see
      // the source over a filtered set, and the answer is a brand new file
      // whose every line was added — the most misleading thing this command
      // could say about a refactor.
      var source = renameSourceIn([
        'M',
        'lib/kept.dart',
        'R100',
        'lib/old.dart',
        'lib/new.dart',
      ], 'lib/new.dart');

      expect(source, 'lib/old.dart');
    });

    test('a file that is not a rename target has no source', () {
      expect(
        renameSourceIn(['M', 'lib/a.dart', 'A', 'lib/b.dart'], 'lib/a.dart'),
        isNull,
      );
    });

    test('walks the pairs rather than scanning for a match', () {
      // A file called `R100` is legal, and a scan looking for status-shaped
      // records would shift everything after it.
      var source = renameSourceIn([
        'A',
        'R100',
        'R100',
        'lib/old.dart',
        'lib/new.dart',
      ], 'lib/new.dart');

      expect(source, 'lib/old.dart');
    });
  });

  group('sequencing', () {
    /// Answers by the shape of the command, so a test states what git said
    /// rather than what order we asked in.
    GitRunner runner(
      Map<String, String> answers, {
      Set<String> fail = const {},
    }) {
      return (directory, arguments, {stdin}) async {
        var line = arguments.join(' ');
        for (var entry in answers.entries) {
          if (line.contains(entry.key)) {
            return GitOutput(
              exitCode: 0,
              stdout: Uint8List.fromList(utf8.encode(entry.value)),
            );
          }
        }
        for (var pattern in fail) {
          if (line.contains(pattern)) {
            return GitOutput(exitCode: 1, stdout: Uint8List(0));
          }
        }
        return GitOutput(exitCode: 1, stdout: Uint8List(0));
      };
    }

    test('infers the base and diffs from the merge base', () async {
      var asked = <String>[];
      var probe = ChangesProbe(
        runGit: (directory, arguments, {stdin}) async {
          asked.add(arguments.join(' '));
          var inner = runner({
            'rev-parse --verify HEAD': 'headsha\n',
            'symbolic-ref': 'origin/main\n',
            'merge-base': 'basesha\n',
            'status': '',
            'diff --name-only': 'lib/a.dart\u0000',
            'diff --no-ext-diff':
                'diff --git a/lib/a.dart b/lib/a.dart\n'
                '--- a/lib/a.dart\n'
                '+++ b/lib/a.dart\n'
                '@@ -1 +1 @@\n'
                '-x\n'
                '+y\n',
          });
          return inner(directory, arguments);
        },
      );

      var set = await probe.probe('/w');

      expect(set.base, 'main');
      expect(set.baseSource, BaseSource.inferred);
      expect(set.mergeBase, 'basesha');
      expect(set.changed.single.path, 'lib/a.dart');
      expect(set.uncommitted, {'lib/a.dart'});
      expect(
        asked.any((a) => a.contains('basesha')),
        isTrue,
        reason: 'the diff runs from the merge base, not from HEAD',
      );
      expect(
        asked.every((a) => a.startsWith('--no-optional-locks')),
        isTrue,
        reason: "every call, or a background refresh fights the user's git",
      );
    });

    test('a configured base is not inferred over', () async {
      var probe = ChangesProbe(
        runGit: runner({
          'rev-parse --verify HEAD': 'headsha\n',
          'merge-base develop HEAD': 'basesha\n',
          'status': '',
          'diff --name-only': '',
          'diff --no-ext-diff': '',
        }),
      );

      var set = await probe.probe('/w', base: 'develop');
      expect(set.base, 'develop');
      expect(set.baseSource, BaseSource.configured);
    });

    test('no base resolves to a state, not a guess', () async {
      // origin/HEAD, main and master all absent. Nothing is diffed against
      // something the user never chose; what is still answerable is shown.
      var probe = ChangesProbe(
        runGit: runner({
          'rev-parse --verify HEAD': 'headsha\n',
          'status': '? scratch.dart\u0000',
          'diff --name-only': 'lib/a.dart\u0000',
          'diff --no-ext-diff':
              'diff --git a/lib/a.dart b/lib/a.dart\n'
              '--- a/lib/a.dart\n'
              '+++ b/lib/a.dart\n'
              '@@ -1 +1 @@\n'
              '-x\n'
              '+y\n',
        }),
      );

      var set = await probe.probe('/w');
      expect(set.base, isNull);
      expect(set.baseSource, BaseSource.none);
      expect(set.mergeBase, isNull);
      expect(
        set.changed.single.path,
        'lib/a.dart',
        reason: 'the uncommitted work is still answerable against HEAD',
      );
      expect(set.untracked.single.path, 'scratch.dart');
    });

    test('a repository with no commit reports its untracked files', () async {
      var probe = ChangesProbe(
        runGit: runner({'status': '? first.dart\u0000'}),
      );

      var set = await probe.probe('/w');
      expect(set.head, isNull);
      expect(set.changed, isEmpty);
      expect(set.untracked.single.path, 'first.dart');
    });

    test("hardens the diff against the user's git config", () async {
      var diffCall = '';
      var probe = ChangesProbe(
        runGit: (directory, arguments, {stdin}) async {
          var line = arguments.join(' ');
          if (line.contains('diff --no-ext-diff')) diffCall = line;
          var inner = runner({
            'rev-parse --verify HEAD': 'headsha\n',
            'symbolic-ref': 'origin/main\n',
            'merge-base': 'basesha\n',
            'status': '',
            'diff --name-only': '',
            'diff --no-ext-diff': '',
          });
          return inner(directory, arguments);
        },
      );

      await probe.probe('/w');

      // Every one of these is a way the user's configuration could otherwise
      // change what the scanner is handed.
      expect(diffCall, contains('core.quotePath=false'));
      expect(diffCall, contains('color.ui=never'));
      expect(diffCall, contains('--no-ext-diff'));
      expect(diffCall, contains('--no-textconv'));
      expect(diffCall, contains('--no-color'));
      expect(diffCall, contains('--src-prefix=a/'));
      expect(diffCall, contains('--dst-prefix=b/'));
    });

    test('asks for untracked files in normal mode, never -uall', () async {
      var statusCall = '';
      var probe = ChangesProbe(
        runGit: (directory, arguments, {stdin}) async {
          var line = arguments.join(' ');
          if (line.contains('status')) statusCall = line;
          return GitOutput(exitCode: 1, stdout: Uint8List(0));
        },
      );

      await probe.probe('/w');

      expect(statusCall, contains('--untracked-files=normal'));
      expect(
        statusCall,
        isNot(contains('-uall')),
        reason: '30,000 rows and a frozen window',
      );
    });
  });
}
