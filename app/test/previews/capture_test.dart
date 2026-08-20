@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';
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

    var runner = PreviewTestRunner(
      packageRoot: packageRoot,
      flutterSdkRoot: flutterRoot!,
      read: () => (entries: [buttons], canvases: const []),
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
      var tree =
          jsonDecode(File(row.tree!).readAsStringSync())
              as Map<String, dynamic>;
      expect(tree['root'], isNotNull);

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
    } finally {
      await runner.dispose();
      Directory(outDir).deleteSync(recursive: true);
    }
  });
}
