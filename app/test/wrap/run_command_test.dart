import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Locate the `dart` executable (see passthrough_command_test for why).
String _resolveDart() {
  if (Platform.resolvedExecutable.endsWith('/dart')) {
    return Platform.resolvedExecutable;
  }
  final r = Process.runSync('/usr/bin/which', ['dart']);
  if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
    return (r.stdout as String).trim();
  }
  throw StateError('Could not locate dart');
}

void main() {
  final dart = _resolveDart();
  // Use absolute path so `dart run` finds the script regardless of the
  // workingDirectory we set on the test process.
  final wrapScript = p.join(Directory.current.path, 'bin', 'wrap.dart');
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('wrap_run');
    File(p.join(project.path, 'flutter_version')).writeAsStringSync('3.44.0\n');
    Directory(p.join(project.path, '.git')).createSync();
  });
  tearDown(() => project.deleteSync(recursive: true));

  test('interesting run is captured into a session dir with meta', () async {
    final result = await Process.run(
      dart,
      [
        'run',
        wrapScript,
        'run',
        '--real',
        '/bin/echo',
        '--kind',
        'flutter',
        '--',
        'run',
        'captured-payload',
      ],
      workingDirectory: project.path,
    );
    expect(result.exitCode, 0);
    final sessions = Directory(
      p.join(project.path, '.flutterware', 'sessions'),
    );
    expect(sessions.existsSync(), isTrue);
    final dirs = sessions.listSync().whereType<Directory>().toList();
    expect(dirs, hasLength(1));
    final out = File(p.join(dirs.single.path, 'output.log')).readAsStringSync();
    expect(out, contains('captured-payload'));
    expect(out, contains('--dart-define=FW_MARKER='));
    expect(
      File(p.join(dirs.single.path, 'meta.json')).existsSync(),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('degrades to a plain run when not inside a flutterware project',
      () async {
    final outside = Directory.systemTemp.createTempSync('wrap_outside');
    addTearDown(() => outside.deleteSync(recursive: true));
    final result = await Process.run(
      dart,
      [
        'run',
        wrapScript,
        'run',
        '--real',
        '/bin/echo',
        '--kind',
        'flutter',
        '--',
        'run',
        'still-runs',
      ],
      workingDirectory: outside.path,
    );
    expect(result.exitCode, 0);
    expect(result.stdout.toString(), contains('still-runs'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('degrade with an unrunnable real binary exits non-zero, no crash',
      () async {
    final outside = Directory.systemTemp.createTempSync('wrap_badbin');
    addTearDown(() => outside.deleteSync(recursive: true));
    final result = await Process.run(
      dart,
      [
        'run',
        wrapScript,
        'run',
        '--real',
        '/no/such/binary_xyz',
        '--kind',
        'flutter',
        '--',
        'run',
      ],
      workingDirectory: outside.path,
    );
    expect(result.exitCode, isNot(0));
    expect(result.exitCode, isNot(255));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
