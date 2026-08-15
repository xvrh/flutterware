import 'dart:io';

import 'package:flutterware/devices.dart';
import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/harness_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  const members = CatalogEntry(
    path: 'demo/team/avatar_tile.dart',
    symbol: 'avatarTileMembers',
    name: 'Members',
    annotation: "Preview(name: 'Members')",
  );
  const wide = CatalogEntry(
    path: 'demo/desktop/table.dart',
    symbol: 'tableWide',
    name: 'Wide',
    annotation: "Preview(name: 'Wide')",
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_preview_harness_test');
    for (var entry in [members, wide]) {
      var file = File(p.join(root.path, entry.path))
        ..parent.createSync(recursive: true);
      file.writeAsStringSync('''
import 'package:flutter/material.dart';

Widget ${entry.symbol}() => const Placeholder();
''');
    }
  });

  tearDown(() => root.deleteSync(recursive: true));

  String harness() =>
      File(p.join(root.path, previewHarnessPath)).readAsStringSync();
  File wrapper(int index) =>
      File(p.join(root.path, previewWrapperDir, 'entry_$index.dart'));

  test('declares every entry, with the path a canvas is matched on', () {
    writePreviewHarness(root.path, [members, wide], canvases: const []);

    expect(harness(), contains("id: r'demo/desktop/table.dart#tableWide'"));
    expect(harness(), contains("path: r'demo/desktop/table.dart'"));
    expect(
      harness(),
      contains("id: r'demo/team/avatar_tile.dart#avatarTileMembers'"),
    );
    // The wrapper is applied inside the thunk, so it runs in the test body
    // under the entry's own canvas rather than at table construction.
    expect(harness(), contains('build: () => _build(fw0.fwPreview'));
  });

  test('emits canvases by device id, never as literal geometry', () {
    // The harness compiles against the *project's* flutterware, whose device
    // table may not be this build's. An id resolves there; a width resolved
    // here would be this build's opinion baked into their program.
    writePreviewHarness(
      root.path,
      [members],
      canvases: [
        const PreviewCanvas('demo', devices: [Devices.iphoneSe]),
        const PreviewCanvas(
          'demo/desktop',
          devices: [Devices.macbookPro],
          orientations: [ScreenOrientation.landscape],
        ),
      ],
    );

    expect(harness(), contains("PreviewCanvas(r'demo', devices: ["));
    expect(harness(), contains("?deviceById(r'iphone-se')"));
    expect(harness(), contains("?orientationById(r'landscape')"));
    expect(
      harness(),
      isNot(contains('${Devices.iphoneSe.width}')),
      reason: 'geometry belongs to the table the harness resolves against',
    );
  });

  test('indices follow sorted ids, so an unchanged catalog is unchanged', () {
    writePreviewHarness(root.path, [members, wide], canvases: const []);
    var first = harness();
    var wrapperSource = wrapper(0).readAsStringSync();

    // Declared the other way round: the order a caller happens to hold them in
    // must not renumber wrappers, or every entry recompiles for nothing.
    writePreviewHarness(root.path, [wide, members], canvases: const []);

    expect(harness(), first);
    expect(wrapper(0).readAsStringSync(), wrapperSource);
  });

  test('leaves files alone when their content is already right', () {
    // A rewritten file is a moved mtime, and a moved mtime is what
    // `SourceInvalidator` reads as an edit — so this is what keeps a warm sync
    // from recompiling the whole catalog every time it looks.
    writePreviewHarness(root.path, [members, wide], canvases: const []);
    var harnessFile = File(p.join(root.path, previewHarnessPath));
    var before = (
      harnessFile.lastModifiedSync(),
      wrapper(0).lastModifiedSync(),
    );

    writePreviewHarness(root.path, [members, wide], canvases: const []);

    expect((
      harnessFile.lastModifiedSync(),
      wrapper(0).lastModifiedSync(),
    ), before);
  });

  test('an entry that went away takes its wrapper with it', () {
    writePreviewHarness(root.path, [members, wide], canvases: const []);
    expect(wrapper(1).existsSync(), isTrue);

    writePreviewHarness(root.path, [members], canvases: const []);

    expect(wrapper(0).existsSync(), isTrue);
    expect(
      wrapper(1).existsSync(),
      isFalse,
      reason: 'an unimported wrapper is still a file the invalidator watches',
    );
  });

  test('says how to run it without flutterware, and what that costs', () {
    writePreviewHarness(root.path, [members], canvases: const []);
    expect(harness(), contains('flutter test $previewHarnessPath'));
    expect(harness(), contains('--use-test-fonts'));
  });
}
