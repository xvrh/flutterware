import 'dart:io';

import 'package:flutterware/src/utils/list_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('list_files_test');
    // A git repository, in the only sense this cares about: something named
    // `.git` marking where ignores start being read.
    Directory(p.join(root.path, '.git')).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, [String content = '']) {
    var file = File(p.join(root.path, p.joinAll(p.split(relative))));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  List<String> list(String directory) => [
    for (var file in listFilesInDirectory(p.join(root.path, directory)))
      p.posix.joinAll(p.split(p.relative(file.path, from: root.path))),
  ]..sort();

  test('a sub-package inherits the repository root .gitignore', () {
    write('.gitignore', 'generated/\n');
    write('packages/app/lib/main.dart');
    write('packages/app/generated/big.dart');

    // The package has no `.gitignore` of its own, which is exactly the case the
    // old walk got wrong: it started reading ignores at the directory it was
    // handed and never looked above it.
    expect(list('packages/app'), ['packages/app/lib/main.dart']);
  });

  test('a nested .gitignore un-ignores what its parent ignored', () {
    write('.gitignore', '*.g.dart\n');
    write('lib/a.g.dart');
    write('lib/keep/.gitignore', '!*.g.dart\n');
    write('lib/keep/b.g.dart');

    // `ignored |= parent` — what the previous implementation did — cannot
    // express this: once a parent had ignored a path no child could take it
    // back, which is the opposite of git's last-match-wins.
    expect(list('.'), [
      '.gitignore',
      'lib/keep/.gitignore',
      'lib/keep/b.g.dart',
    ]);
  });

  test('.git and .dart_tool are skipped without being ignored anywhere', () {
    write('.git/objects/ab/cdef');
    write('.dart_tool/package_config.json');
    write('lib/main.dart');

    expect(list('.'), ['lib/main.dart']);
  });

  test('.git/info/exclude is honoured', () {
    write('.git/info/exclude', 'scratch/\n');
    write('scratch/notes.dart');
    write('lib/main.dart');

    expect(list('.'), ['lib/main.dart']);
  });

  test('symlinks are dropped rather than followed', () {
    write('lib/main.dart');
    write('elsewhere/big.dart');
    Link(
      p.join(root.path, 'lib', 'link'),
    ).createSync(p.join(root.path, 'elsewhere'));

    expect(list('lib'), ['lib/main.dart']);
  });

  test('an untracked file is listed — this is not `git ls-files`', () {
    write('lib/brand_new.dart');

    expect(list('.'), ['lib/brand_new.dart']);
  });

  test('gitRootOf finds the enclosing repository, and stops', () {
    write('packages/app/lib/main.dart');

    expect(
      gitRootOf(p.join(root.path, 'packages', 'app', 'lib')),
      p.normalize(root.path),
    );
    // Nothing above the temp directory is a repository — unless the system
    // temp directory happens to sit in one, which is why this only asserts it
    // is not *this* root.
    var above = gitRootOf(Directory.systemTemp.path);
    expect(above, isNot(p.normalize(root.path)));
  });

  test('a directory the repository ignores still lists its own files', () {
    // Asking for a directory by name outranks a rule above it that covers the
    // whole directory. The real case is the dependencies plugin counting lines
    // in `~/.pub-cache/hosted/…` under a home directory that is itself a git
    // repository with `.pub-cache/` in its `.gitignore` — inheritance there
    // would report every cached package as empty.
    write('.gitignore', 'cache/\n');
    write('cache/pkg/lib/a.dart');
    write('cache/pkg/build/out.dart');

    expect(list('cache/pkg'), [
      // `build/` survives: nothing inside the directory ignores it, and the
      // rule that would have is the one being stepped over.
      'cache/pkg/build/out.dart',
      'cache/pkg/lib/a.dart',
    ]);
    expect(list('.'), [
      '.gitignore',
    ], reason: 'from above, it is still ignored');
  });

  test('an explicit ignoreRoot overrides the repository lookup', () {
    write('.gitignore', 'generated/\n');
    write('packages/app/lib/main.dart');
    write('packages/app/generated/big.dart');

    expect(list('packages/app'), [
      'packages/app/lib/main.dart',
    ], reason: 'the repository root ignores generated/');
    expect(
      [
        for (var file in listFilesInDirectory(
          p.join(root.path, 'packages', 'app'),
          ignoreRoot: p.join(root.path, 'packages', 'app'),
        ))
          p.posix.joinAll(p.split(p.relative(file.path, from: root.path))),
      ]..sort(),
      ['packages/app/generated/big.dart', 'packages/app/lib/main.dart'],
      reason: 'reading ignores from the package down, nothing ignores it',
    );
  });
}
