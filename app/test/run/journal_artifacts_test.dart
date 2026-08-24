import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/journal.dart';
import 'package:path/path.dart' as p;

/// The bound on a run's pictures. The story is bounded by rotation already;
/// this is the evidence, which is where the weight is — measured at ~187KB a
/// beat, or a quarter of a gigabyte an hour of ordinary tapping.
void main() {
  late Directory root;
  late RunHandle handle;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw-journal-artifacts');
    handle = RunHandle(
      worktree: '/w',
      worktreeName: 'w',
      device: 'macos',
      entrypoint: 'lib/main.dart',
      launcherPid: 1,
      startedAt: DateTime(2026, 8, 24),
      package: '.',
    ).publish(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// One step's worth of files under a single stamp, as `_Capture.write`
  /// names them.
  void writeStep(String stamp, {required int bytes}) {
    var dir = Directory(journalArtifactsDirFor(handle)!)
      ..createSync(recursive: true);
    File(p.join(dir.path, '$stamp.png'))
        .writeAsBytesSync(List.filled(bytes, 0));
    File(p.join(dir.path, '$stamp.texts.json')).writeAsStringSync('[]');
  }

  List<String> remaining() =>
      Directory(journalArtifactsDirFor(handle)!)
          .listSync()
          .map((e) => p.basename(e.path))
          .toList()
        ..sort();

  test('under budget, nothing is touched', () {
    writeStep('100-1', bytes: 1000);
    writeStep('200-1', bytes: 1000);

    expect(boundJournalArtifacts(handle, maxBytes: 1 << 20), 0);
    expect(remaining(), hasLength(4));
  });

  test('over budget, the oldest steps go whole', () {
    writeStep('100-1', bytes: 4000);
    writeStep('200-1', bytes: 4000);
    writeStep('300-1', bytes: 4000);

    var freed = boundJournalArtifacts(handle, maxBytes: 9000);

    expect(freed, greaterThan(0));
    expect(remaining(), [
      '200-1.png',
      '200-1.texts.json',
      '300-1.png',
      '300-1.texts.json',
    ], reason: 'a step loses its picture and its texts together, never half');
  });

  test('the newest step is never let go, however big', () {
    writeStep('100-1', bytes: 50000);

    expect(boundJournalArtifacts(handle, maxBytes: 10), 0);
    expect(
      remaining(),
      hasLength(2),
      reason: 'a bound that can delete the step being looked at is a bug',
    );
  });

  test('a run with no artifacts directory is not an error', () {
    expect(boundJournalArtifacts(handle, maxBytes: 10), 0);
  });
}
