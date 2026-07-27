import 'dart:io';

import 'package:flutterware_app/src/catalog/catalog_entry.dart';
import 'package:flutterware_app/src/catalog/entrypoint_generator.dart';
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
        "const fwDemo = Demo(name: 'Members', "
        'wrapper: wrapInApp);',
      ),
    );
    expect(wrapper(0), contains('const fwBuilder = fw0.avatarTileMembers;'));
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
}
