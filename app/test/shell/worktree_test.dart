import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';

void main() {
  group('parseWorktreeList', () {
    test('reads a normal listing and marks the first as main', () {
      var worktrees = parseWorktreeList('''
worktree /repo
HEAD 1a2b3c
branch refs/heads/main

worktree /repo/../wt-explorer
HEAD 4d5e6f
branch refs/heads/feature/explorer
''');

      expect(worktrees, hasLength(2));
      expect(worktrees.first.path, '/repo');
      expect(worktrees.first.branch, 'main');
      expect(worktrees.first.isMain, isTrue);
      expect(worktrees.last.branch, 'feature/explorer');
      expect(worktrees.last.isMain, isFalse);
    });

    test('handles a detached worktree', () {
      var worktrees = parseWorktreeList('''
worktree /repo
HEAD 1a2b3c
detached
''');
      expect(worktrees.single.branch, isNull);
      expect(worktrees.single.head, '1a2b3c');
      // No branch and no title: fall back to the directory name.
      expect(worktrees.single.displayName, 'repo');
    });

    test('ignores attributes it does not know', () {
      var worktrees = parseWorktreeList('''
worktree /repo
HEAD 1a2b3c
branch refs/heads/main
locked
prunable gitdir file points to non-existent location

worktree /repo/other
HEAD 4d5e6f
branch refs/heads/x
''');
      expect(worktrees.map((w) => w.branch), ['main', 'x']);
    });

    test('tolerates a missing trailing blank line', () {
      var worktrees = parseWorktreeList(
        'worktree /repo\nHEAD 1a2b3c\nbranch refs/heads/main',
      );
      expect(worktrees.single.branch, 'main');
    });

    test('returns nothing for empty output', () {
      expect(parseWorktreeList(''), isEmpty);
    });
  });

  group('displayName precedence', () {
    test('a contributed title beats the branch', () {
      var worktree = const Worktree(
        path: '/repo',
        branch: 'claude/nostalgic-maxwell',
      );
      expect(worktree.displayName, 'claude/nostalgic-maxwell');
      expect(
        worktree.withTitle('Worktree explorer design').displayName,
        'Worktree explorer design',
      );
    });
  });

  group('discovery', () {
    test('falls back to the directory when git fails', () async {
      var discovery = WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 128, '', 'not a git repository'),
      );
      var worktrees = await discovery.discover('.');
      expect(worktrees, hasLength(1));
      expect(worktrees.single.isMain, isTrue);
    });

    test('falls back when git is not installed', () async {
      var discovery = WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            throw ProcessException('git', []),
      );
      expect(await discovery.discover('.'), hasLength(1));
    });

    test('returns what git reports', () async {
      var discovery = WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async => ProcessResult(
          0,
          0,
          'worktree /a\nbranch refs/heads/main\n\nworktree /b\n'
              'branch refs/heads/dev\n',
          '',
        ),
      );
      expect((await discovery.discover('.')).map((w) => w.branch), [
        'main',
        'dev',
      ]);
    });

    test('names each linked worktree the way git does', () async {
      // `--force` lets two worktrees share a directory name; git still keeps
      // its own names apart, which is the whole reason they are the identity.
      var discovery = WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async => ProcessResult(
          0,
          0,
          'worktree /repo\nbranch refs/heads/main\n\n'
              'worktree /a/feature\nbranch refs/heads/feature\n\n'
              'worktree /b/feature\nbranch refs/heads/other\n',
          '',
        ),
        readGitPointer: (path) => switch (path) {
          '/a/feature' => 'gitdir: /repo/.git/worktrees/feature\n',
          '/b/feature' => 'gitdir: /repo/.git/worktrees/feature1\n',
          _ => null,
        },
      );

      expect((await discovery.discover('.')).map((w) => w.name), [
        '~',
        'feature',
        'feature1',
      ]);
    });

    test(
      'a worktree whose pointer cannot be read keeps its directory',
      () async {
        var discovery = WorktreeDiscovery(
          runProcess: (_, _, {workingDirectory}) async => ProcessResult(
            0,
            0,
            'worktree /repo\nbranch refs/heads/main\n\n'
                'worktree /a/feature\nbranch refs/heads/feature\n',
            '',
          ),
          readGitPointer: (_) => null,
        );
        expect((await discovery.discover('.')).last.name, 'feature');
      },
    );
  });

  group('gitNameFrom', () {
    test('reads the name off an absolute pointer', () {
      expect(
        gitNameFrom('gitdir: /Users/x/proj/.git/worktrees/my-feature\n'),
        'my-feature',
      );
    });

    test('reads it off a relative one too', () {
      // `git worktree add --relative-paths` writes these; the name is still the
      // last component, so nothing has to resolve the path.
      expect(
        gitNameFrom('gitdir: ../../.git/worktrees/my-feature'),
        'my-feature',
      );
    });

    test('is null for anything that is not a linked worktree pointer', () {
      expect(gitNameFrom(null), isNull);
      expect(gitNameFrom(''), isNull);
      expect(gitNameFrom('ref: refs/heads/main'), isNull);
      // The main checkout: `.git` is a directory, so there is nothing to read.
      expect(gitNameFrom('gitdir: /repo/.git'), isNull);
    });
  });

  group('a worktree is named the way git names it', () {
    test('the main checkout is ~', () {
      // It has no admin directory, and no ordinary token is safe: git will give
      // a *linked* worktree the name `main` if its directory is called that.
      var main = const Worktree(path: '/x/repo', isMain: true);
      expect(main.name, '~');
      expect(main.name, Worktree.mainName);
    });

    test(
      'a linked one is called what git calls it, not what the folder is',
      () {
        var worktree = const Worktree(
          path: '/somewhere/totally-different',
          gitName: 'feature',
        );
        // Survives `git worktree move`, which the directory name does not.
        expect(worktree.name, 'feature');
        expect(worktree.directoryName, 'totally-different');
      },
    );

    test('displayName shows the folder, never the ~', () {
      // A detached main checkout has no title and no branch, and `~` on a tab
      // would tell you nothing about which checkout you are looking at.
      var detached = const Worktree(path: '/x/repo', head: 'abc', isMain: true);
      expect(detached.name, '~');
      expect(detached.displayName, 'repo');
    });

    test('a title survives being renamed', () {
      var worktree = const Worktree(path: '/x/wt', gitName: 'feature1');
      expect(worktree.withTitle('Fix the thing').name, 'feature1');
    });
  });
}
