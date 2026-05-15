import 'dart:io';
import 'package:flutterware_app/src/wrap/project_resolution.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wrap_proj'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('findProjectRoot walks up to the flutter_version marker', () {
    File(p.join(tmp.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    final nested = Directory(p.join(tmp.path, 'a', 'b'))
      ..createSync(recursive: true);
    final root = findProjectRoot(nested);
    expect(root?.resolveSymbolicLinksSync(),
        equals(tmp.resolveSymbolicLinksSync()));
  });

  test('findProjectRoot returns null when there is no marker', () {
    final nested = Directory(p.join(tmp.path, 'a'))..createSync();
    expect(findProjectRoot(nested), isNull);
  });

  test('resolveWorktreeName reads the gitdir pointer from a .git file', () {
    File(p.join(tmp.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    File(p.join(tmp.path, '.git'))
        .writeAsStringSync('gitdir: /repo/.git/worktrees/feature-x\n');
    expect(resolveWorktreeName(tmp), equals('feature-x'));
  });

  test('resolveWorktreeName falls back to the dir name for a main checkout',
      () {
    File(p.join(tmp.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    Directory(p.join(tmp.path, '.git')).createSync();
    expect(resolveWorktreeName(tmp), equals(p.basename(tmp.path)));
  });
}
