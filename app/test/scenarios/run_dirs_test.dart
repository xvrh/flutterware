import 'dart:io';

import 'package:flutterware_app/src/scenarios/run_dirs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Nothing swept scenario run directories, and a recorded panel run is half a
/// gigabyte. These are the rules that keep that bounded without taking the
/// pictures somebody is looking at.
void main() {
  late Directory root;
  late String runs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_run_dirs_test');
    runs = scenarioRunsDirIn(root.path);
    Directory(runs).createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// A run directory with something in it, so a sweep has to recurse.
  String make(String name) {
    var dir = Directory(p.join(runs, name))..createSync(recursive: true);
    File(p.join(dir.path, 'run.json')).writeAsStringSync('{}');
    return dir.path;
  }

  List<String> remaining() =>
      [for (var entity in Directory(runs).listSync()) p.basename(entity.path)]
        ..sort();

  test('keeps the newest few and drops the rest', () {
    for (var stamp in ['1700000000001', '1700000000002', '1700000000003']) {
      make(stamp);
    }
    make('1700000000004');
    make('1700000000005');

    expect(sweepScenarioRuns(root.path, keep: 3), 2);
    expect(remaining(), ['1700000000003', '1700000000004', '1700000000005']);
  });

  // Drift walks back from the newest stamped run looking for the previous
  // report and skips `panel-*` entirely. Sweeping the two series together
  // would let a busy panel session age out the run drift is about to read.
  test('the two series are kept apart', () {
    for (var i = 1; i <= 4; i++) {
      make('170000000000$i');
      make('panel-170000000000$i');
    }

    sweepScenarioRuns(root.path, keep: 2);
    expect(remaining(), [
      '1700000000003',
      '1700000000004',
      'panel-1700000000003',
      'panel-1700000000004',
    ]);
  });

  // `--output` may point anywhere, including here, and the order is the name
  // rather than the mtime — so a run could otherwise sweep away the report it
  // had just written.
  test('a protected directory survives whatever its name', () {
    make('1700000000001');
    make('1700000000002');
    var mine = make('1700000000000');

    sweepScenarioRuns(root.path, keep: 1, protect: {mine});
    expect(remaining(), ['1700000000000', '1700000000002']);
  });

  // A matrix run writes a directory per point *inside* the stamped one and
  // reports those as its outputs, so an exact-match protect would leave the
  // stamped parent — the thing this sweep deletes — unnamed and fair game.
  test('protecting a point protects the run that holds it', () {
    make('1700000000001');
    make('1700000000002');
    var point = Directory(p.join(runs, '1700000000000', 'iphone-13'))
      ..createSync(recursive: true);
    File(p.join(point.path, 'run.json')).writeAsStringSync('{}');
    File(p.join(runs, '1700000000000', 'index.json')).writeAsStringSync('{}');

    sweepScenarioRuns(root.path, keep: 1, protect: {point.path});
    expect(remaining(), ['1700000000000', '1700000000002']);
    expect(
      File(p.join(runs, '1700000000000', 'index.json')).existsSync(),
      isTrue,
    );
  });

  test('a directory the runs did not name is never touched', () {
    make('1700000000001');
    make('1700000000002');
    make('ci-artifacts');
    make('latest');

    sweepScenarioRuns(root.path, keep: 1);
    expect(remaining(), ['1700000000002', 'ci-artifacts', 'latest']);
  });

  test('a package that has never run is not an error', () {
    var empty = Directory.systemTemp.createTempSync('fw_no_runs');
    try {
      expect(sweepScenarioRuns(empty.path), 0);
    } finally {
      empty.deleteSync(recursive: true);
    }
  });
}
