// Where a library sits is who reads it.
//
// A scene's home was always its position — the nearest group above it. A
// library's was a `libraries:` list somebody kept by hand, reached through an
// Attach menu. Two rules answering one question, and only one of them visible
// in the folders; the cost was a file the tool would happily write and then
// let you never use. This is the second rule deleted.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scene/discovery.dart';
import 'package:flutterware_app/src/scene/group_file.dart';
import 'package:flutterware_app/src/scene/skeletons.dart';
import 'package:flutterware_app/src/scene/tokens_file.dart';
import 'package:flutterware_app/src/scene/ui/listing_words.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_scene_position'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A folder that is a group: the declaration, and one scene so it is worth
  /// looking at.
  void group(String folder) {
    var directory = Directory(p.join(root.path, folder))
      ..createSync(recursive: true);
    File(p.join(directory.path, sceneGroupFileName))
        .writeAsStringSync(emitGroupSkeleton());
  }

  void library(String path) {
    var file = File(p.join(root.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(emitTokensSkeleton(tokensSymbolFor(file.path)));
  }

  List<String> readersOf(String path) => [
    for (var g in discoverPackage(
      root.path,
    ).groupsReading(p.join(root.path, path)))
      g.name,
  ];

  List<String> librariesOf(String folder) {
    var scan = discoverPackage(root.path);
    var found = scan.groups.firstWhere(
      (g) => p.basename(g.directory) == folder,
    );
    return [for (var l in scan.librariesFor(found)) l.symbol];
  }

  test('a library in a folder is read by that folder alone', () {
    group('lib/demo');
    group('lib/marketing');
    library('lib/demo/brand.tokens.dart');
    expect(readersOf('lib/demo/brand.tokens.dart'), ['demo']);
    expect(librariesOf('demo'), ['brandTokens']);
    expect(librariesOf('marketing'), isEmpty);
  });

  test('a library above several folders is read by all of them', () {
    group('lib/demo');
    group('lib/marketing');
    library('lib/palette.tokens.dart');
    expect(readersOf('lib/palette.tokens.dart'), ['demo', 'marketing']);
    expect(librariesOf('demo'), ['paletteTokens']);
    expect(librariesOf('marketing'), ['paletteTokens']);
  });

  test('a library beside a folder is read by nobody, and says so', () {
    group('lib/demo');
    library('lib/design/brand.tokens.dart');
    expect(readersOf('lib/design/brand.tokens.dart'), isEmpty);
    expect(
      readBy(readersOf('lib/design/brand.tokens.dart')),
      'read by nothing yet',
    );
  });

  test('a nested group reads its own and everything above it', () {
    group('lib/demo');
    group('lib/demo/promos');
    library('lib/palette.tokens.dart');
    library('lib/demo/brand.tokens.dart');
    library('lib/demo/promos/loud.tokens.dart');
    // Outermost first: the shared palette before the folder's own.
    expect(librariesOf('promos'), [
      'paletteTokens',
      'brandTokens',
      'loudTokens',
    ]);
    expect(librariesOf('demo'), ['paletteTokens', 'brandTokens']);
    expect(readersOf('lib/demo/brand.tokens.dart'), ['demo', 'promos']);
    expect(readersOf('lib/demo/promos/loud.tokens.dart'), ['promos']);
  });

  test('the rule itself, without a walk around it', () {
    expect(readsLibrary('/a/demo', '/a/demo/brand.tokens.dart'), isTrue);
    expect(readsLibrary('/a/demo', '/a/brand.tokens.dart'), isTrue);
    expect(readsLibrary('/a/demo', '/a/other/brand.tokens.dart'), isFalse);
    // Not below: a group above a library reads nothing of it.
    expect(readsLibrary('/a', '/a/demo/brand.tokens.dart'), isFalse);
    // Spelling is not position: the same folder said two ways is one folder.
    expect(
      readsLibrary('/a/demo', '/a/demo/../demo/brand.tokens.dart'),
      isTrue,
    );
  });
}
