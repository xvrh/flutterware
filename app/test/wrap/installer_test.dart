import 'dart:io';
import 'package:flutterware_app/src/wrap/installer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Directory sdk;
  late Directory project;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wrap_inst');
    // A fake "shared SDK".
    sdk = Directory(p.join(tmp.path, 'sharedsdk'))..createSync();
    Directory(p.join(sdk.path, 'bin')).createSync();
    Directory(p.join(sdk.path, 'bin', 'cache')).createSync();
    File(p.join(sdk.path, 'bin', 'flutter')).writeAsStringSync('#real\n');
    File(p.join(sdk.path, 'bin', 'dart')).writeAsStringSync('#real\n');
    File(p.join(sdk.path, 'bin', 'internal')).writeAsStringSync('x\n');
    File(p.join(sdk.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    project = Directory(p.join(tmp.path, 'project'))..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('installMirror builds a facade: real bin/, symlinked entries, shims',
      () {
    final mirror = installMirror(
      sharedSdk: sdk,
      projectRoot: project,
      wrapExe: '/cache/wrap',
    );
    expect(mirror.path, p.join(project.path, 'flutterware', 'sdk'));

    // Top-level non-bin entries are symlinks to the shared SDK.
    expect(FileSystemEntity.isLinkSync(p.join(mirror.path, 'pubspec.yaml')),
        isTrue);
    // bin/ is a real directory.
    expect(
        FileSystemEntity.isDirectorySync(p.join(mirror.path, 'bin')), isTrue);
    expect(FileSystemEntity.isLinkSync(p.join(mirror.path, 'bin')), isFalse);
    // bin/cache and bin/internal are symlinks.
    expect(FileSystemEntity.isLinkSync(p.join(mirror.path, 'bin', 'cache')),
        isTrue);
    // bin/flutter and bin/dart are real shim files, not symlinks.
    final flutterShim = File(p.join(mirror.path, 'bin', 'flutter'));
    expect(FileSystemEntity.isLinkSync(flutterShim.path), isFalse);
    expect(flutterShim.readAsStringSync(), contains('KIND="flutter"'));
    expect(File(p.join(mirror.path, 'bin', 'dart')).readAsStringSync(),
        contains('KIND="dart"'));
  });

  test('installMirror is idempotent — re-running rebuilds cleanly', () {
    installMirror(sharedSdk: sdk, projectRoot: project, wrapExe: '/c/wrap');
    final mirror =
        installMirror(sharedSdk: sdk, projectRoot: project, wrapExe: '/c/wrap');
    expect(File(p.join(mirror.path, 'bin', 'flutter')).existsSync(), isTrue);
  });
}
