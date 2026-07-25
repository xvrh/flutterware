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
  });
}
