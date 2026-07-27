import 'dart:io';

import 'package:flutterware_app/src/catalog/discovery.dart';
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

@Demo(name: 'Members')
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
@Demo(name: 'X', formFactor: FormFactor.desktop, size: kWide, wrapper: shell)
Widget a() => const Placeholder();
''');

    expect(
      scan().entries.single.annotation,
      "Demo(name: 'X', formFactor: FormFactor.desktop, size: kWide, "
      'wrapper: shell)',
    );
  });

  test('finds annotated constructors, torn off with .new', () {
    // rimbaud's ~168 demos are all Widget classes, so this is the shape that
    // matters most for migration.
    write('tile.dart', '''
import 'package:flutter/widgets.dart';

class AvatarTileDemo extends StatelessWidget {
  @Demo(name: 'Avatar tile')
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
  @Demo(name: 'Named')
  const Demos.named();

  @Demo(name: 'Static')
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

  test('a file with several entries derives a group from its filename', () {
    write('team/member_list_view.dart', '''
@Demo(name: 'Few')
Widget few() => const Placeholder();

@Demo(name: 'Empty')
Widget empty() => const Placeholder();
''');

    expect(
      scan().entries.map((e) => e.group),
      everyElement('Member list view'),
    );
  });

  test('a file with one entry derives no group', () {
    write('team/avatar_tile.dart', '''
@Demo(name: 'Avatar tile')
Widget avatarTile() => const Placeholder();
''');

    expect(scan().entries.single.group, isNull);
  });

  test('a declared group wins over the derived one, and spans files', () {
    write('case/upload_capture.dart', '''
@Demo(name: 'Capture', group: 'Upload')
Widget capture() => const Placeholder();
''');
    write('case/upload_progress.dart', '''
@Demo(name: 'In progress', group: 'Upload')
Widget progress() => const Placeholder();

@Demo(name: 'Failed', group: 'Upload')
Widget failed() => const Placeholder();
''');

    expect(scan().entries.map((e) => e.group), everyElement('Upload'));
  });

  test('a declared id overrides the derived identity', () {
    write('a.dart', '''
@Demo(name: 'X', id: 'stable-id')
Widget x() => const Placeholder();
''');

    expect(scan().entries.single.id, 'stable-id');
  });

  test('stacked annotations on one declaration are rejected, not collapsed', () {
    // Both derive `path#symbol`, so one entry would be unreachable. This is the
    // single case where the design refuses rather than reports.
    write('a.dart', '''
@Demo(name: 'Few')
@Demo(name: 'Empty')
Widget list() => const Placeholder();
''');

    var result = scan();
    expect(result.ok, isFalse);
    expect(
      result.diagnostics.map((d) => d.message).join(),
      contains('same id'),
    );
  });

  test('an explicit id resolves a stacked-annotation clash', () {
    write('a.dart', '''
@Demo(name: 'Few')
@Demo(name: 'Empty', id: 'a.dart#list.empty')
Widget list() => const Placeholder();
''');

    expect(scan().ok, isTrue);
  });

  test('a target with required parameters is an error', () {
    write('a.dart', '''
@Demo(name: 'X')
Widget x(int count) => const Placeholder();
''');

    var result = scan();
    expect(result.ok, isFalse);
    expect(result.entries, isEmpty);
    expect(result.diagnostics.single.message, contains('required parameters'));
  });

  test('optional and named parameters are fine', () {
    write('a.dart', '''
@Demo(name: 'X')
Widget x({int count = 0}) => const Placeholder();
''');

    expect(scan().ok, isTrue);
    expect(scan().entries, hasLength(1));
  });

  test('a wrong return type is reported but still discovered', () {
    write('a.dart', '''
@Demo(name: 'X')
String x() => 'not a widget';
''');

    var result = scan();
    expect(result.entries, hasLength(1), reason: 'the guest compile judges it');
    expect(result.ok, isTrue, reason: 'a warning, not a refusal');
    expect(result.diagnostics.single.message, contains('does not return'));
  });

  test('the name falls back to the symbol when none is declared', () {
    write('a.dart', '''
@Demo()
Widget avatarTile() => const Placeholder();
''');

    expect(scan().entries.single.name, 'avatarTile');
  });

  test('files without an annotation are skipped by the prefilter', () {
    write('a.dart', 'int x = 1;');
    expect(scan().entries, isEmpty);
  });
}
