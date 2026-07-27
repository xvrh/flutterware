import 'dart:io';

import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/entrypoint_generator.dart';
import 'package:flutterware_app/src/catalog/shell_descriptor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late EntrypointGenerator generator;

  const members = CatalogEntry(
    path: 'demo/team/avatar_tile.dart',
    symbol: 'avatarTileMembers',
    name: 'Members',
    annotation: "Demo(name: 'Members', wrapper: wrapInApp)",
  );
  const empty = CatalogEntry(
    path: 'demo/team/avatar_tile.dart',
    symbol: 'avatarTileEmpty',
    name: 'Empty',
    annotation: "Demo(name: 'Empty', wrapper: wrapInApp)",
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_entrypoint_test');
    var demoDir = Directory(p.join(root.path, 'demo', 'team'))
      ..createSync(recursive: true);
    File(p.join(demoDir.path, 'avatar_tile.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';

import '../shell.dart';

Widget avatarTileMembers() => const Placeholder();
Widget avatarTileEmpty() => const Placeholder();
''');
    generator = EntrypointGenerator(
      outputDir: p.join(root.path, 'build', 'entrypoint'),
      projectRoot: root.path,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  String wrapper(int index) => File(
    p.join(root.path, 'build', 'entrypoint', 'entry_$index.dart'),
  ).readAsStringSync();
  String entrypoint() => File(generator.entrypointPath).readAsStringSync();

  test('emits the annotation verbatim, never interpreted', () {
    generator.select(members);
    expect(
      wrapper(0),
      contains(
        "Demo get fwDemo => Demo(name: 'Members', "
        'wrapper: wrapInApp);',
      ),
    );
    expect(
      wrapper(0),
      contains('Widget Function() get fwBuilder => fw0.avatarTileMembers;'),
    );
    // Not const, and this is the whole point: a const holding a function
    // tear-off is inlined into the entrypoint's constant pool, and a reload
    // carrying only the entrypoint cannot re-resolve it against a demo file it
    // does not contain. The guest renders `Lookup failed: wrapInApp in
    // @methods in file:...` instead of the demo.
    expect(wrapper(0), isNot(contains('const fwDemo')));
    expect(wrapper(0), isNot(contains('const fwBuilder')));
  });

  test('carries the demo file imports, re-relativised', () {
    generator.select(members);
    // Package URIs pass through untouched.
    expect(wrapper(0), contains("import 'package:flutter/material.dart';"));
    // '../shell.dart' resolves to <root>/demo/shell.dart, which from
    // <root>/build/entrypoint/ is three levels up.
    expect(wrapper(0), contains("import '../../demo/shell.dart';"));
    expect(wrapper(0), isNot(contains("import '../shell.dart';")));
  });

  test('a fresh prefix per entry, so no prefix is ever rebound', () {
    generator.select(members);
    generator.select(empty);

    expect(entrypoint(), contains("import 'entry_0.dart' as fw0;"));
    expect(entrypoint(), contains("import 'entry_1.dart' as fw1;"));
    expect(wrapper(0), contains('as fw0;'));
    expect(wrapper(1), contains('as fw1;'));
  });

  test('the entrypoint accumulates and selects the active entry', () {
    generator.select(members);
    expect(entrypoint(), contains('fw0.fwDemo.transform()'));

    generator.select(empty);
    expect(entrypoint(), contains("import 'entry_0.dart' as fw0;"));
    expect(entrypoint(), contains('fw1.fwDemo.transform()'));
    expect(entrypoint(), isNot(contains('fw0.fwDemo.transform()')));

    generator.select(members);
    expect(entrypoint(), contains('fw0.fwDemo.transform()'));
    expect(generator.visited, hasLength(2), reason: 'revisits reuse a wrapper');
  });

  test('selects through getters, never top-level finals', () {
    generator.select(members);
    expect(entrypoint(), contains('Preview get _preview'));
    expect(entrypoint(), contains('Widget Function() get _builder'));
    expect(entrypoint(), isNot(contains('final _preview')));
  });

  test('reports what to invalidate: the wrapper only on first visit', () {
    expect(generator.select(members), hasLength(2));
    expect(generator.select(empty), hasLength(2));
    expect(
      generator.select(members),
      hasLength(1),
      reason: 'a revisit rewrites only the entrypoint',
    );
  });

  group('registerAll — what makes one compiler safe to share', () {
    test('imports every entry, so a select only ever changes main.dart', () {
      generator.registerAll([members, empty]);
      expect(generator.visited, [members, empty]);
      expect(
        generator.select(empty),
        hasLength(1),
        reason:
            'the wrapper is already registered, so only the entrypoint is '
            'invalidated',
      );
      expect(entrypoint(), contains("import 'entry_0.dart' as fw0;"));
      expect(
        entrypoint(),
        contains("import 'entry_1.dart' as fw1;"),
        reason: 'an entry nobody has selected is still imported',
      );
    });

    test('a second client selecting first is not what adds the wrapper', () {
      // The hazard this closes: with lazy registration, whoever selects an
      // entry first adds its wrapper, and that is the only compile whose delta
      // carries it. A second client selecting the same entry later would be
      // handed a delta with the wrapper missing — unchanged since the baseline
      // — and its guest, which never had that library, would reload nothing.
      generator.registerAll([members, empty]);

      var first = generator.select(empty);
      var second = generator.select(empty);

      expect(first.map((u) => p.basename(u.path)), ['main.dart']);
      expect(
        second.map((u) => p.basename(u.path)),
        ['main.dart'],
        reason: 'both clients see the same delta, whoever got there first',
      );
    });

    test('is idempotent, so a rescan does not renumber live wrappers', () {
      generator.registerAll([members, empty]);
      var before = wrapper(0);
      expect(generator.registerAll([members, empty]), isEmpty);
      expect(wrapper(0), before);
    });
  });

  test('keys the rendered subtree by entry, so switching remounts state', () {
    generator.select(members);
    expect(entrypoint(), contains('ValueKey<String>(_entryId)'));
    expect(
      entrypoint(),
      contains(
        "String get _entryId => r'demo/team/avatar_tile.dart"
        "#avatarTileMembers';",
      ),
    );
  });

  group('a shell', () {
    const shell = ShellDescriptor(
      path: 'demo/shell.dart',
      symbol: 'wrapInApp',
      axes: [
        ShellAxis(
          name: 'flavor',
          typeName: 'Flavor',
          defaultSource: 'Flavor.dev',
        ),
        ShellAxis(name: 'compact', typeName: 'bool', defaultSource: 'false'),
      ],
    );
    const wrapped = CatalogEntry(
      path: 'demo/team/avatar_tile.dart',
      symbol: 'avatarTileMembers',
      name: 'Members',
      annotation: "Demo(name: 'Members', wrapper: wrapInApp)",
      wrapper: 'wrapInApp',
      shellId: 'demo/shell.dart#wrapInApp',
    );

    setUp(() {
      File(p.join(root.path, 'demo', 'shell.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';

import 'flavors.dart';

@CatalogShell()
Widget wrapInApp(Widget child, {Flavor flavor = Flavor.dev}) => child;
''');
      generator.shells = {shell.id: shell};
    });

    test('is called by name, which is where the axes still exist', () {
      // Through `preview.wrapper` they would be gone: that field is a
      // WidgetWrapper, and the typedef erases every named parameter.
      generator.select(wrapped);
      expect(
        wrapper(0),
        contains('Widget _fwWrapInShell(Widget child) => wrapInApp('),
      );
      expect(entrypoint(), contains('_shellWrap ?? preview.wrapper'));
    });

    test('hands the enum its own values, which is where options come from', () {
      generator.select(wrapped);
      expect(
        wrapper(0),
        contains(
          "flavor: CatalogAxes.instance.pick('flavor', Flavor.values, "
          'Flavor.dev),',
        ),
      );
    });

    test('a bool axis is a flag, having no values to hand over', () {
      generator.select(wrapped);
      expect(
        wrapper(0),
        contains("compact: CatalogAxes.instance.flag('compact', false),"),
      );
    });

    test("carries the shell's file and its imports, for the axis types", () {
      // `Flavor` has to resolve where the generated call is written, and that
      // is not necessarily where the demo is: it may be declared beside the
      // shell, or imported by it.
      generator.select(wrapped);
      expect(wrapper(0), contains("import '../../demo/shell.dart';"));
      expect(wrapper(0), contains("import '../../demo/flavors.dart';"));
    });

    test('an entry with no shell says so, and goes the old way', () {
      generator.select(members);
      expect(wrapper(0), contains('String? get fwShellId => null;'));
      expect(
        wrapper(0),
        contains('Widget Function(Widget)? get fwShellWrap => null;'),
      );
    });

    test('the scope wraps the entry, so a turn rebuilds the shell', () {
      generator.select(wrapped);
      expect(entrypoint(), contains('CatalogAxesScope('));
      expect(entrypoint(), contains('shellId: _shellId,'));
    });
  });
}
