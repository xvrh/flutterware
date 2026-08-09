import 'dart:io';

import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_discovery_test'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String content) {
    var file = File(p.join(root.path, 'demo', relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  ScanResult scan() => CatalogScanner(projectRoot: root.path).scan();

  test('finds annotated top-level functions', () {
    write('team/avatar_tile.dart', '''
import 'package:flutter/widgets.dart';

@Preview(name: 'Members')
Widget avatarTileMembers() => const Placeholder();

Widget notAnEntry() => const Placeholder();
''');

    var result = scan();
    expect(result.ok, isTrue);
    expect(result.entries, hasLength(1));
    expect(result.entries.single.name, 'Members');
    expect(result.entries.single.symbol, 'avatarTileMembers');
    expect(result.entries.single.path, 'demo/team/avatar_tile.dart');
    expect(
      result.entries.single.id,
      'demo/team/avatar_tile.dart#avatarTileMembers',
    );
  });

  test('carries the annotation verbatim, never interpreted', () {
    write('a.dart', '''
@Preview(name: 'X', size: kWide, wrapper: shell)
Widget a() => const Placeholder();
''');

    expect(
      scan().entries.single.annotation,
      "Preview(name: 'X', size: kWide, wrapper: shell)",
    );
  });

  test('finds annotated constructors, torn off with .new', () {
    // rimbaud's ~168 demos are all Widget classes, so this is the shape that
    // matters most for migration.
    write('tile.dart', '''
import 'package:flutter/widgets.dart';

class AvatarTileDemo extends StatelessWidget {
  @Preview(name: 'Avatar tile')
  const AvatarTileDemo({super.key});

  @override
  Widget build(BuildContext context) => const Placeholder();
}
''');

    var entry = scan().entries.single;
    expect(entry.symbol, 'AvatarTileDemo.new');
    expect(entry.name, 'Avatar tile');
  });

  test('finds annotated named constructors and static methods', () {
    write('b.dart', '''
class Demos {
  @Preview(name: 'Named')
  const Demos.named();

  @Preview(name: 'Static')
  static Widget build() => const Placeholder();
}
''');

    expect(
      scan().entries.map((e) => e.symbol),
      containsAll(['Demos.named', 'Demos.build']),
    );
  });

  test(
    'registration is the whole filter: an unregistered name is invisible',
    () {
      write('c.dart', '''
@Tablet(name: 'Ignored')
Widget tablet() => const Placeholder();

@Preview(name: 'Seen')
Widget preview() => const Placeholder();
''');

      var result = scan();
      expect(result.entries.map((e) => e.name), ['Seen']);

      // Registering it makes it visible, with no closure analysis involved.
      var registered = CatalogScanner(
        projectRoot: root.path,
        previewAnnotations: const ['Demo', 'Preview', 'Tablet'],
      ).scan();
      expect(
        registered.entries.map((e) => e.name),
        containsAll(['Ignored', 'Seen']),
      );
    },
  );

  group('MultiPreview', () {
    // Flutter's one-annotation-many-previews base class. Both of these used to
    // be silent: unregistered, the previews are simply missing; registered, the
    // generated wrapper fails to compile pointing at generated code.
    const brightness = '''
final class BrightnessPreview extends MultiPreview {
  const BrightnessPreview();

  @override
  List<Preview> get previews => const [Preview(name: 'Light')];
}
''';

    test('unregistered is none of our business', () {
      // Two reasons, and the second is the binding one. It may be serving
      // Flutter's own previewer perfectly well, so warning off a bare-name
      // match is this scanner volunteering an opinion about a file it has no
      // stake in. And knowing whether the name is *used* would mean parsing the
      // files the prefilter skips — 20ms becomes 478ms to serve a case with no
      // users.
      write('brightness.dart', brightness);
      write('a.dart', '''
@BrightnessPreview()
Widget themed() => const Placeholder();
''');

      var result = scan();
      expect(result.entries, isEmpty);
      expect(result.diagnostics, isEmpty);
    });

    test('is refused, with the reason, when it is registered', () {
      write('brightness.dart', brightness);

      var result = CatalogScanner(
        projectRoot: root.path,
        previewAnnotations: const ['Demo', 'Preview', 'BrightnessPreview'],
      ).scan();
      expect(result.ok, isFalse);
      expect(
        result.diagnostics.single.message,
        allOf(contains('BrightnessPreview'), contains('previewAnnotations')),
      );
    });

    test('is found in a file that declares no entries of its own', () {
      // The prefilter reads for annotations, and the class that extends
      // MultiPreview is routinely declared away from anything using it — hence
      // `MultiPreview` joining the annotations as a prefilter term.
      write('annotations/brightness.dart', brightness);
      write('a.dart', '''
@Preview(name: 'Ordinary')
Widget ordinary() => const Placeholder();
''');

      var result = CatalogScanner(
        projectRoot: root.path,
        previewAnnotations: const ['Demo', 'Preview', 'BrightnessPreview'],
      ).scan();
      expect(result.entries.map((e) => e.name), ['Ordinary']);
      expect(
        result.diagnostics.single.location,
        'demo/annotations/brightness.dart',
      );
    });
  });

  test('a file with several entries derives a group from its filename', () {
    write('team/member_list_view.dart', '''
@Preview(name: 'Few')
Widget few() => const Placeholder();

@Preview(name: 'Empty')
Widget empty() => const Placeholder();
''');

    expect(
      scan().entries.map((e) => e.group),
      everyElement('Member list view'),
    );
  });

  test('a file with one entry derives no group', () {
    write('team/avatar_tile.dart', '''
@Preview(name: 'Avatar tile')
Widget avatarTile() => const Placeholder();
''');

    expect(scan().entries.single.group, isNull);
  });

  test('a declared group wins over the derived one, and spans files', () {
    write('case/upload_capture.dart', '''
@Preview(name: 'Capture', group: 'Upload')
Widget capture() => const Placeholder();
''');
    write('case/upload_progress.dart', '''
@Preview(name: 'In progress', group: 'Upload')
Widget progress() => const Placeholder();

@Preview(name: 'Failed', group: 'Upload')
Widget failed() => const Placeholder();
''');

    expect(scan().entries.map((e) => e.group), everyElement('Upload'));
  });

  test('a declared id overrides the derived identity', () {
    write('a.dart', '''
@Preview(name: 'X', id: 'stable-id')
Widget x() => const Placeholder();
''');

    expect(scan().entries.single.id, 'stable-id');
  });

  test('a target with required parameters is an error', () {
    write('a.dart', '''
@Preview(name: 'X')
Widget x(int count) => const Placeholder();
''');

    var result = scan();
    expect(result.ok, isFalse);
    expect(result.entries, isEmpty);
    expect(result.diagnostics.single.message, contains('required parameters'));
  });

  test('optional and named parameters are fine', () {
    write('a.dart', '''
@Preview(name: 'X')
Widget x({int count = 0}) => const Placeholder();
''');

    expect(scan().ok, isTrue);
    expect(scan().entries, hasLength(1));
  });

  test('a wrong return type is reported but still discovered', () {
    write('a.dart', '''
@Preview(name: 'X')
String x() => 'not a widget';
''');

    var result = scan();
    expect(result.entries, hasLength(1), reason: 'the guest compile judges it');
    expect(result.ok, isTrue, reason: 'a warning, not a refusal');
    expect(result.diagnostics.single.message, contains('does not return'));
  });

  test('the name falls back to the symbol when none is declared', () {
    write('a.dart', '''
@Preview()
Widget avatarTile() => const Placeholder();
''');

    expect(scan().entries.single.name, 'avatarTile');
  });

  test('files without an annotation are skipped by the prefilter', () {
    write('a.dart', 'int x = 1;');
    expect(scan().entries, isEmpty);
  });

  test('stacked annotations take an ordinal, so no id has to be declared', () {
    // Stacking is one of the two ways to spell variants, and it used to be the
    // one place `id:` was mandatory: both annotations derived `path#symbol`,
    // and the collision was a scan error.
    write('variants.dart', '''
@Preview(name: 'Light')
@Preview(name: 'Dark')
Widget themed() => const Placeholder();
''');

    var result = scan();
    expect(result.ok, isTrue);
    expect(result.entries.map((e) => e.id), [
      'demo/variants.dart#themed',
      'demo/variants.dart#themed#1',
    ]);
  });

  test('a declared id still wins, and two of them are still refused', () {
    write('pinned.dart', '''
@Preview(name: 'A', id: 'shared')
Widget a() => const Placeholder();

@Preview(name: 'B', id: 'shared')
Widget b() => const Placeholder();
''');

    var result = scan();
    expect(result.ok, isFalse);
    expect(result.diagnostics.single.message, contains('"shared"'));
  });

  group('shells are not discovered at all', () {
    test('a shell file yields no entries and no complaint', () {
      // Nothing marks it and nothing looks for it. A shell is an ordinary
      // `Widget Function(Widget)` that happens to build a `PreviewShell`, and
      // the catalog learns about it only when the guest renders one and
      // reports the axes it asked for.
      write('shell.dart', '''
import 'package:flutter/widgets.dart';
import 'package:flutterware/ui_catalog.dart';

enum Flavor { dev, staging, prod }

Widget wrapInApp(Widget child) => PreviewShell(
  'app',
  builder: (context, topBar) => topBar.flag('compact', false)
      ? child
      : const Placeholder(),
);
''');

      var result = scan();
      expect(result.ok, isTrue);
      expect(result.entries, isEmpty);
      expect(result.diagnostics, isEmpty);
    });

    test('naming a wrapper is just an annotation argument now', () {
      // It used to be linked to a discovered shell by symbol, which is what
      // made two files declaring `wrapInApp` an ambiguity the scan had to
      // refuse. Nothing reads it here any more — it rides along in the
      // annotation's source text and is resolved by the compiler.
      write('a.dart', '''
@Preview(name: 'Wrapped', wrapper: wrapInApp)
Widget a() => const Placeholder();

@Preview(name: 'Bare')
Widget b() => const Placeholder();
''');

      var result = scan();
      expect(result.ok, isTrue);
      // Sorted by id, which is path plus symbol: `a` before `b`.
      expect(result.entries.map((e) => e.name), ['Wrapped', 'Bare']);
      expect(
        result.entries.firstWhere((e) => e.name == 'Wrapped').annotation,
        "Preview(name: 'Wrapped', wrapper: wrapInApp)",
      );
    });
  });

  group('rescanning the same scanner', () {
    // The scan root is the whole package, so the daemon rescans whenever any
    // `.dart` file is touched — and that rescan sits on the hot-reload path.
    // Re-reading every file there is what these guard against; what they assert
    // is that being incremental changes nothing about the answer.
    late CatalogScanner scanner;

    setUp(() {
      scanner = CatalogScanner(projectRoot: root.path);
      write('counter.dart', '''
@Preview(name: 'Counter')
Widget counter() => const Placeholder();
''');
    });

    /// Files written in the same millisecond as the last scan would keep their
    /// cached result. A real edit is never that quick; a test is.
    void touch(String relative) => File(
      p.join(root.path, 'demo', relative),
    ).setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));

    test('an edit to an existing file is picked up', () {
      expect(scanner.scan().entries.map((e) => e.name), ['Counter']);

      write('counter.dart', '''
@Preview(name: 'Counter')
Widget counter() => const Placeholder();

@Preview(name: 'Stepper')
Widget stepper() => const Placeholder();
''');
      touch('counter.dart');

      var result = scanner.scan();
      expect(result.entries.map((e) => e.name), ['Counter', 'Stepper']);
      // Two entries in one file, so the file's own name becomes their group —
      // derived per file, which is why it survives being cached per file.
      expect(result.entries.map((e) => e.group), ['Counter', 'Counter']);
    });

    test('a new file appears and a deleted one goes', () {
      scanner.scan();

      write('tile.dart', '''
@Preview(name: 'Tile')
Widget tile() => const Placeholder();
''');
      expect(scanner.scan().entries.map((e) => e.name), ['Counter', 'Tile']);

      File(p.join(root.path, 'demo', 'counter.dart')).deleteSync();
      expect(scanner.scan().entries.map((e) => e.name), ['Tile']);
    });

    test('an annotation removed takes its entry with it', () {
      expect(scanner.scan().entries, hasLength(1));

      // Straight past the prefilter now, which is the case a cache keyed on
      // "did this file ever have an entry" would get wrong.
      write('counter.dart', 'Widget counter() => const Placeholder();\n');
      touch('counter.dart');

      expect(scanner.scan().entries, isEmpty);
    });

    test('a duplicate id is still refused after a rescan', () {
      scanner.scan();

      // Cross-file, so it cannot be cached per file and has to be recomputed on
      // every assembly.
      write('a.dart', "@Preview(name: 'A', id: 'same')\nWidget a() => x;\n");
      write('b.dart', "@Preview(name: 'B', id: 'same')\nWidget b() => x;\n");

      var result = scanner.scan();
      expect(result.ok, isFalse);
      expect(
        result.diagnostics.where((d) => d.isError).single.message,
        contains('resolve to the same id "same"'),
      );
    });
  });
}
