import 'dart:io';
import 'package:flutterware_app/src/wrap/shim_template.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late File shim;
  late File realMarker;
  late File wrapMarker;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wrap_shim');
    // A "real binary" double that records it was called and echoes argv.
    realMarker = File(p.join(tmp.path, 'real.called'));
    final fakeReal = File(p.join(tmp.path, 'fake_real'))
      ..writeAsStringSync('#!/usr/bin/env bash\necho "real:'
          r'$*'
          '" >>"${realMarker.path}"\n');
    Process.runSync('chmod', ['+x', fakeReal.path]);
    // A "wrap exe" double — note it must accept the `run ... -- ...` argv.
    wrapMarker = File(p.join(tmp.path, 'wrap.called'));
    final fakeWrap = File(p.join(tmp.path, 'fake_wrap'))
      ..writeAsStringSync('#!/usr/bin/env bash\necho "wrap:'
          r'$*'
          '" >>"${wrapMarker.path}"\n');
    Process.runSync('chmod', ['+x', fakeWrap.path]);

    shim = File(p.join(tmp.path, 'flutter'))
      ..writeAsStringSync(renderShim(
        realBinary: fakeReal.path,
        kind: 'flutter',
        wrapExe: fakeWrap.path,
      ));
    Process.runSync('chmod', ['+x', shim.path]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProcessResult invoke(List<String> args, {required Directory cwd}) =>
      Process.runSync(shim.path, args, workingDirectory: cwd.path);

  test('no marker -> straight to the real binary, no audit log', () {
    final cwd = Directory(p.join(tmp.path, 'plain'))..createSync();
    invoke(['run'], cwd: cwd);
    expect(realMarker.existsSync(), isTrue);
    expect(wrapMarker.existsSync(), isFalse);
  });

  test('interesting run (flutter run) is dispatched to the wrap exe', () {
    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    File(p.join(proj.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    invoke(['--no-color', 'run', '--machine'], cwd: proj);
    expect(wrapMarker.existsSync(), isTrue);
    expect(wrapMarker.readAsStringSync(), contains('run --real'));
    final audit = File(p.join(proj.path, '.flutterware', 'wrap-audit.log'));
    expect(audit.readAsStringSync(), contains('interesting'));
  });

  test('noise (flutter pub get) goes to the real binary, audited as noise', () {
    final proj = Directory(p.join(tmp.path, 'proj2'))..createSync();
    File(p.join(proj.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    invoke(['pub', 'get'], cwd: proj);
    expect(realMarker.existsSync(), isTrue);
    expect(wrapMarker.existsSync(), isFalse);
    final audit = File(p.join(proj.path, '.flutterware', 'wrap-audit.log'));
    expect(audit.readAsStringSync(), contains('noise'));
  });

  test('interesting run degrades to real when the wrap exe is missing', () {
    final proj = Directory(p.join(tmp.path, 'proj3'))..createSync();
    File(p.join(proj.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    // Re-render the shim pointing at a non-existent wrap exe.
    shim.writeAsStringSync(renderShim(
      realBinary: File(p.join(tmp.path, 'fake_real')).path,
      kind: 'flutter',
      wrapExe: '/no/such/wrap_exe',
    ));
    Process.runSync('chmod', ['+x', shim.path]);
    invoke(['run'], cwd: proj);
    expect(realMarker.existsSync(), isTrue);
  });
}
