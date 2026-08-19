import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/run_git.dart';

void main() {
  group('environmentForGit', () {
    test('strips every variable that redirects git to another repository', () {
      var env = environmentForGit({
        'GIT_DIR': '/elsewhere/.git',
        'GIT_WORK_TREE': '/elsewhere',
        'GIT_INDEX_FILE': '/elsewhere/.git/index',
        'GIT_COMMON_DIR': '/elsewhere/.git',
        'GIT_OBJECT_DIRECTORY': '/elsewhere/.git/objects',
        'GIT_ALTERNATE_OBJECT_DIRECTORIES': '/elsewhere/.git/objects',
        'GIT_QUARANTINE_PATH': '/elsewhere/.git/objects/incoming',
        'GIT_PREFIX': 'sub/dir/',
        'GIT_NAMESPACE': 'fork',
        'GIT_GRAFT_FILE': '/elsewhere/.git/info/grafts',
        'GIT_SHALLOW_FILE': '/elsewhere/.git/shallow',
        'PATH': '/usr/bin',
      });

      expect(env, {'PATH': '/usr/bin'});
    });

    test('strips case-insensitively, the way Windows resolves them', () {
      var env = environmentForGit({
        'git_dir': '/elsewhere/.git',
        'Git_Work_Tree': '/elsewhere',
        'HOME': '/home/someone',
      });

      expect(env, {'HOME': '/home/someone'});
    });

    test('keeps the variables the user set up their machine with', () {
      // Authentication, identity and config are the parent environment doing
      // its job — none of them can point a command at the wrong repository,
      // and dropping GIT_SSH_COMMAND breaks every fetch over ssh.
      var kept = {
        'GIT_SSH_COMMAND': 'ssh -i ~/.ssh/work',
        'GIT_ASKPASS': '/usr/local/bin/askpass',
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_AUTHOR_NAME': 'Someone',
        'GIT_CONFIG_GLOBAL': '/home/someone/.gitconfig',
      };

      expect(environmentForGit(kept), kept);
    });

    test('defaults to the real parent environment', () {
      // Platform.environment cannot carry GIT_DIR under the test runner, so
      // what is checkable here is that the copy is the parent's — the
      // filtering itself is covered above.
      expect(environmentForGit(), environmentForGit(Platform.environment));
    });
  });

  group('runGit', () {
    test('asks git for the repository the arguments name', () async {
      // The full leak cannot be reproduced in-process — GIT_DIR would have to
      // be in this test runner's own environment — but the plumbing can be
      // exercised: a real spawn, through the rebuilt environment, answering
      // for the directory it was pointed at.
      var dir = Directory.systemTemp.createTempSync('run_git_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      await runGit(['init', '-q'], workingDirectory: dir.path);

      var result = await runGit([
        'rev-parse',
        '--show-toplevel',
      ], workingDirectory: dir.path);

      expect(result.exitCode, 0);
      expect(
        Directory('${result.stdout}'.trim()).resolveSymbolicLinksSync(),
        Directory(dir.path).resolveSymbolicLinksSync(),
      );
    });
  });
}
