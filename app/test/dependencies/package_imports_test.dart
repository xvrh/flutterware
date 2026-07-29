import 'dart:io';

import 'package:flutterware_app/src/dependencies/model/package_imports.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fw_imports');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  PackageImports gather() => PackageImports.gather(
    root.path,
    root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')),
  );

  test('records the file, the URI and the library', () {
    write('lib/a.dart', "import 'package:collection/collection.dart';");

    var reference = gather()['collection'].single;
    expect(reference.path, p.join('lib', 'a.dart'));
    expect(reference.uri, 'package:collection/collection.dart');
    expect(reference.library, 'collection.dart');
    expect(reference.isExport, isFalse);
    expect(reference.scope, ImportScope.lib);
  });

  test('a nested library URI keeps its whole path', () {
    write('lib/a.dart', "import 'package:foo/src/deep/thing.dart';");
    expect(gather()['foo'].single.library, 'src/deep/thing.dart');
  });

  test('exports are recorded and marked', () {
    write('lib/a.dart', "export 'package:foo/foo.dart';");
    expect(gather()['foo'].single.isExport, isTrue);
  });

  test('relative and dart: imports are ignored', () {
    write('lib/a.dart', '''
import 'dart:io';
import 'other.dart';
import 'package:foo/foo.dart';
''');
    expect(gather().byPackage.keys, ['foo']);
  });

  test('scopes are read off the first path segment', () {
    write('lib/a.dart', "import 'package:foo/foo.dart';");
    write('test/a_test.dart', "import 'package:foo/foo.dart';");
    write('integration_test/b_test.dart', "import 'package:foo/foo.dart';");
    write('tool/gen.dart', "import 'package:foo/foo.dart';");
    write('bin/main.dart', "import 'package:foo/foo.dart';");
    write('elsewhere/x.dart', "import 'package:foo/foo.dart';");

    expect(gather().scopesOf('foo'), [
      ImportScope.lib,
      ImportScope.test,
      ImportScope.tool,
      ImportScope.other,
    ]);
  });

  test('fileCount counts files, not imports', () {
    // One file importing two libraries of the same package is one file.
    write('lib/a.dart', '''
import 'package:foo/foo.dart';
import 'package:foo/extra.dart';
''');
    var imports = gather();
    expect(imports['foo'], hasLength(2));
    expect(imports.fileCount('foo'), 1);
  });

  group('isTestOnly', () {
    test('is true when nothing outside test refers to it', () {
      write('test/a_test.dart', "import 'package:foo/foo.dart';");
      expect(gather().isTestOnly('foo'), isTrue);
    });

    test('is false as soon as lib refers to it', () {
      write('test/a_test.dart', "import 'package:foo/foo.dart';");
      write('lib/a.dart', "import 'package:foo/foo.dart';");
      expect(gather().isTestOnly('foo'), isFalse);
    });

    test('is false for a package nothing refers to', () {
      // "Never imported" is not "test-only" — the caller must not read an
      // absent package as a misplaced dependency.
      write('lib/a.dart', "import 'package:bar/bar.dart';");
      expect(gather().isTestOnly('foo'), isFalse);
    });
  });

  group('conditional imports', () {
    // Reading only the default URI reports a package used solely on one
    // platform as never referenced.
    test('every branch counts, and carries its condition', () {
      write('lib/a.dart', '''
import 'package:stub/stub.dart'
    if (dart.library.io) 'package:native/native.dart'
    if (dart.library.js_interop) 'package:web_impl/web_impl.dart';
''');

      var imports = gather();
      expect(imports.byPackage.keys, {'stub', 'native', 'web_impl'});
      expect(imports['stub'].single.condition, isNull);
      expect(imports['native'].single.condition, 'dart.library.io');
      expect(imports['web_impl'].single.condition, 'dart.library.js_interop');
    });

    test('a conditional export counts too', () {
      write('lib/a.dart', '''
export 'package:stub/stub.dart' if (dart.library.io) 'package:native/n.dart';
''');
      expect(gather()['native'].single.isExport, isTrue);
    });

    test('relative and dart: branches are still ignored', () {
      write('lib/a.dart', '''
import 'stub.dart' if (dart.library.io) 'dart:io';
''');
      expect(gather().byPackage, isEmpty);
    });
  });

  group('asset references', () {
    PackageImports gatherWith(Map<String, Object?> flutter) =>
        PackageImports.gather(root.path, const [], flutterSection: flutter);

    test('an asset path reaching into a package is a reference', () {
      var imports = gatherWith({
        'assets': ['packages/my_icons/img/a.png', 'assets/local.png'],
      });

      expect(
        imports.assetsOf('my_icons').single.path,
        'packages/my_icons/img/a.png',
      );
      expect(imports.assetsOf('my_icons').single.isFont, isFalse);
      expect(imports.isReferenced('my_icons'), isTrue);
      // A path with no `packages/` prefix belongs to this package.
      expect(imports.assetsByPackage.keys, ['my_icons']);
    });

    test('the map form with flavors is read too', () {
      // Flutter 3.19 allowed `- path:` / `flavors:` in place of a bare string.
      var imports = gatherWith({
        'assets': [
          {
            'path': 'packages/my_icons/img/',
            'flavors': ['dev'],
          },
        ],
      });
      expect(imports.assetsOf('my_icons'), hasLength(1));
    });

    test('fonts are read, and marked as fonts', () {
      var imports = gatherWith({
        'fonts': [
          {
            'family': 'Icons',
            'fonts': [
              {'asset': 'packages/my_icons/fonts/icons.ttf'},
              {'asset': 'fonts/local.ttf'},
            ],
          },
        ],
      });

      expect(imports.assetsOf('my_icons').single.isFont, isTrue);
    });

    test('an asset reference is never test-only', () {
      write('test/a_test.dart', "import 'package:my_icons/my_icons.dart';");
      var imports = PackageImports.gather(
        root.path,
        root.listSync(recursive: true).whereType<File>(),
        flutterSection: {
          'assets': ['packages/my_icons/img/a.png'],
        },
      );

      // The Dart side says test-only; the asset ships with the app, so the
      // package cannot move to dev_dependencies.
      expect(imports.scopesOf('my_icons'), [ImportScope.test]);
      expect(imports.isTestOnly('my_icons'), isFalse);
    });

    test('a malformed flutter section is not fatal', () {
      // User-written YAML of a shape that keeps changing; a surprise here is a
      // missing reference, not an exception on the way into the panel.
      for (var flutter in <Map<String, Object?>>[
        {'assets': 'not-a-list'},
        {
          'assets': [42, null],
        },
        {'fonts': 'nope'},
        {
          'fonts': [
            {'family': 'X'},
          ],
        },
        {'assets': const []},
      ]) {
        expect(gatherWith(flutter).assetsByPackage, isEmpty);
      }
    });

    test('no flutter section at all is fine', () {
      expect(
        PackageImports.gather(root.path, const []).assetsByPackage,
        isEmpty,
      );
      expect(
        PackageImports.gather(
          root.path,
          const [],
          flutterSection: null,
        ).isReferenced('anything'),
        isFalse,
      );
    });
  });

  test('a file that will not parse is skipped, not fatal', () {
    write('lib/broken.dart', 'class {{{ not dart');
    write('lib/fine.dart', "import 'package:foo/foo.dart';");
    expect(gather()['foo'], hasLength(1));
  });

  test('an unknown package reads as no references', () {
    write('lib/a.dart', "import 'package:foo/foo.dart';");
    var imports = gather();
    expect(imports['nope'], isEmpty);
    expect(imports.fileCount('nope'), 0);
    expect(imports.scopesOf('nope'), isEmpty);
  });
}
