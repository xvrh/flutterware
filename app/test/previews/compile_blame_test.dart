import 'package:flutterware_app/src/previews/catalog_entry.dart';
import 'package:flutterware_app/src/previews/compile_blame.dart';
import 'package:test/test.dart';

void main() {
  const root = '/project';

  const members = CatalogEntry(
    path: 'demo/team/avatar_tile.dart',
    symbol: 'members',
    name: 'Members',
    annotation: "Demo(name: 'Members')",
  );
  const empty = CatalogEntry(
    path: 'demo/team/avatar_tile.dart',
    symbol: 'empty',
    name: 'Empty',
    annotation: "Demo(name: 'Empty')",
  );
  const counter = CatalogEntry(
    path: 'demo/counter.dart',
    symbol: 'counter',
    name: 'Counter',
    annotation: "Demo(name: 'Counter')",
  );

  CompileBlame blame(List<String> output) => CompileBlame.of(
    output,
    entries: const [members, empty, counter],
    projectRoot: root,
    workingDirectory: root,
  );

  test('blames the entries declared in the failing file', () {
    // Verbatim shape of what frontend_server emits.
    var result = blame([
      "demo/counter.dart:5:25: Error: Method not found: 'Nope'.",
      'Widget counter() => Nope();',
      '                    ^^^^',
    ]);

    expect(result.entryIds, {counter.id});
    expect(result.unattributed, isEmpty);
  });

  test('a broken file takes every entry declared in it', () {
    var result = blame([
      'demo/team/avatar_tile.dart:9:1: Error: Expected a declaration.',
    ]);

    expect(result.entryIds, {
      members.id,
      empty.id,
    }, reason: 'neither can be reached, so neither can be served');
  });

  test('an error nobody declares an entry in is not blamed on anyone', () {
    var result = blame(['demo/shell.dart:3:1: Error: Expected a declaration.']);

    expect(result.entryIds, isEmpty);
    expect(result.unattributed, {'/project/demo/shell.dart'});
    expect(
      result.isEmpty,
      isTrue,
      reason:
          'dropping entries cannot fix a broken helper, so this stays fatal',
    );
  });

  test('warnings are not grounds for dropping a working demo', () {
    var result = blame([
      "demo/counter.dart:5:25: Warning: Unused import 'dart:io'.",
      'demo/counter.dart:7:1: Context: Declared here.',
    ]);

    expect(result.entryIds, isEmpty);
    expect(result.unattributed, isEmpty);
  });

  test('accepts absolute paths and file: URIs', () {
    expect(blame(['/project/demo/counter.dart:5:1: Error: Nope.']).entryIds, {
      counter.id,
    });
    expect(
      blame(['file:///project/demo/counter.dart:5:1: Error: Nope.']).entryIds,
      {counter.id},
    );
  });

  test('resolves relative paths against the compiler working directory', () {
    var result = CompileBlame.of(
      ['../demo/counter.dart:5:1: Error: Nope.'],
      entries: const [counter],
      projectRoot: root,
      workingDirectory: '$root/app',
    );

    expect(result.entryIds, {counter.id});
  });

  test('several failing files are blamed together, in one pass', () {
    var result = blame([
      'demo/counter.dart:5:1: Error: Nope.',
      'demo/team/avatar_tile.dart:9:1: Error: Also nope.',
    ]);

    expect(result.entryIds, {counter.id, members.id, empty.id});
  });
}
