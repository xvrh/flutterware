@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/embedder/build_directory.dart';
import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

/// End-to-end: the real `examples/example` package, a real `flutter_tester`,
/// a real capture — the lane the preview comparison renders both sides in.
/// Slow (a cold harness compile), so everything is exercised in one warm
/// sequence rather than one test per assertion.
void main() {
  test('captures the frame and the tree, and the pixels reproduce', () async {
    var flutterRoot = Platform.environment['FLUTTER_ROOT'];
    expect(
      flutterRoot,
      isNotNull,
      reason: 'flutter test always sets FLUTTER_ROOT',
    );
    // app/ → the repo root, the workspace this test runs in.
    var repoRoot = Directory.current.parent.path;
    var packageRoot = p.join(repoRoot, 'examples', 'example');
    var outDir = Directory.systemTemp.createTempSync('preview_capture').path;

    var scan = CatalogScanner(projectRoot: packageRoot).scan();
    var buttons = scan.entries.singleWhere(
      (entry) => entry.id == 'demo/buttons.dart#buttons',
    );

    // In a claimed directory, exactly as the comparison builds: its head is
    // the worktree the panel's warm runner lives on, so the production lane
    // is never the default `build/flutterware` — and the depth is what the
    // generated imports have to climb out of.
    // **An orphan, planted before anything spawns.** Bringing a harness up is
    // where the sweep runs, and that link is the one thing neither the rules'
    // unit tests nor the handle assertions below can reach: a host that records
    // and forgets perfectly but never sweeps passes both and leaves every
    // previous crash's guest running.
    var orphan = await Process.start('sleep', const ['60']);
    addTearDown(() => orphan.kill(ProcessSignal.sigkill));
    File(p.join(flutterwareRunDir(), 'guest-${orphan.pid}.json'))
        .writeAsStringSync(
          jsonEncode({
            'pid': orphan.pid,
            'startedAt': DateTime.now().toIso8601String(),
            // A pid that has certainly been reaped, so the owner reads as gone.
            'ownerPid': await _deadPid(),
            'ownerRecordedAt': DateTime.now().toIso8601String(),
            'what': 'a crash left this',
          }),
        );

    var buildDirectory = claimBuildDirectory(
      packageRoot,
      root: comparisonBuildRoot,
    );
    var runner = PreviewTestRunner(
      packageRoot: packageRoot,
      flutterSdkRoot: flutterRoot!,
      read: () => (entries: [buttons], canvases: const []),
      buildDirectory: buildDirectory,
    );
    try {
      var rows = <PreviewCaptureRow>[];
      await runner.capture(
        entryIds: [buttons.id],
        outDir: p.join(outDir, 'one'),
        onRow: (row) async => rows.add(row),
      );
      var row = rows.single;
      expect(row.compileError, isNull);
      expect(row.failure, isNull);
      var image = File(row.image!);
      // Raw rgba8888: the length is the dimensions, no decode to check.
      expect(image.lengthSync(), row.width * row.height * 4);
      expect(row.width, greaterThan(0));
      var tree = jsonDecode(
        File(row.tree!).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(tree['root'], isNotNull);

      // **A ratio, not a fraction.** `1` is the logical size — right for a
      // diff and a thumbnail, and wrong for a picture somebody reads a 16pt
      // glyph in, which is why the word had to stop being `scale`: at 2 the
      // same entry comes back at twice the side and four times the bytes, and
      // a caller staging a 3× phone asks for 3 rather than for a fraction it
      // has to work out.
      var doubled = <PreviewCaptureRow>[];
      await runner.capture(
        entryIds: [buttons.id],
        outDir: p.join(outDir, 'doubled'),
        pixelRatio: 2,
        tree: false,
        onRow: (found) async => doubled.add(found),
      );
      expect(doubled.single.width, row.width * 2);
      expect(doubled.single.height, row.height * 2);
      expect(File(doubled.single.image!).lengthSync(), image.lengthSync() * 4);

      // The lane's whole argument over the embedder: the same entry
      // photographed again is byte-identical, because the clock is fake and
      // the shutter falls on the same instant.
      var first = image.readAsBytesSync();
      var again = <PreviewCaptureRow>[];
      await runner.capture(
        entryIds: [buttons.id],
        outDir: p.join(outDir, 'two'),
        onRow: (row) async => again.add(row),
      );
      expect(File(again.single.image!).readAsBytesSync(), first);
      // Everything the run built stayed inside its claim: the dill, the
      // generated harness, the wrappers, the log. The warm lane's directory
      // gained none of it, which is the isolation the claim exists for.
      var claimed = Directory(p.join(packageRoot, buildDirectory));
      expect(
        claimed.listSync().map((entity) => p.basename(entity.path)),
        containsAll([
          'previews.dill',
          'previews_harness.dart',
          'previews_harness',
          'previews.log',
        ]),
      );

      // **The guest is registered while it lives.** A `flutter_tester` is the
      // one child that survives its owner — measured, 19 of them orphaned to
      // `ppid` 1 on one machine — and the handle is what lets the next process
      // finish a kill this one never reached. Asserted here because the rules
      // are unit-tested and the *wiring* is not: a host that records nothing
      // passes every one of those and leaks exactly as before.
      expect(
        _guestHandles(),
        isNotEmpty,
        reason: 'the running harness announced itself to the sweeper',
      );
      await orphan.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () =>
            fail('bringing a harness up left a previous crash running'),
      );
    } finally {
      await runner.dispose();
      releaseBuildDirectory(
        packageRoot,
        buildDirectory,
        root: comparisonBuildRoot,
      );
      Directory(outDir).deleteSync(recursive: true);
    }
    expect(
      Directory(p.join(packageRoot, buildDirectory)).existsSync(),
      isFalse,
    );
    // And withdrawn when it dies, so a later sweep has nothing to read about a
    // guest that is already gone.
    expect(_guestHandles(), isEmpty);
  });
}

/// A pid that is certainly gone: a process started and waited for.
Future<int> _deadPid() async {
  var process = await Process.start('true', const []);
  await process.exitCode;
  return process.pid;
}

/// The handles this test process is currently answering for.
///
/// Scoped to this pid so a developer's own running Studio, which writes into
/// the same directory, neither fails this test nor is disturbed by it.
List<File> _guestHandles() {
  var owned = <File>[];
  for (var entity in Directory(flutterwareRunDir()).listSync()) {
    if (entity is! File) continue;
    if (!p.basename(entity.path).startsWith('guest-')) continue;
    try {
      var json = jsonDecode(entity.readAsStringSync());
      if (json is Map && json['ownerPid'] == pid) owned.add(entity);
    } on Object {
      // Somebody else's litter.
    }
  }
  return owned;
}
