import 'dart:io';

import 'package:flutterware_app/src/assets/model/asset_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The rules in here are Flutter's, not ours, and each test names the one it
/// pins. `examples/example` carries the same cases as files you can look at —
/// see `examples/example/assets/README.md` — but the checks live in a temp
/// directory so they do not need the workspace to have been resolved.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_assets_test'));
  tearDown(() => root.deleteSync(recursive: true));

  String appRoot() => p.join(root.path, 'app');
  String depRoot() => p.join(root.path, 'dep');

  void write(String relative, String content) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// A config resolving two packages, which is what makes the `packages/…`
  /// prefix reachable without a `pub get`.
  ///
  /// Both are always in the config and neither is always in the bundle — that
  /// gap is the pub-workspace case, and several tests below live in it.
  void writePackageConfig() {
    write('app/.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "dep",
      "rootUri": "../../dep",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    },
    {
      "name": "deep",
      "rootUri": "../../deep",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    }
  ]
}
''');
  }

  Future<AssetCatalog> resolve() => AssetCatalog.resolve(
    rootPackageRoot: appRoot(),
    packageConfigPath: p.join(appRoot(), '.dart_tool', 'package_config.json'),
  );

  setUp(writePackageConfig);

  test('a directory declaration does not recurse', () async {
    write('app/pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/images/
''');
    write('app/assets/images/logo.png', 'png');
    write('app/assets/images/icons/star.png', 'png');

    var catalog = await resolve();

    expect(catalog.byKey.keys, ['assets/images/logo.png']);
    expect(
      catalog.byKey['assets/images/icons/star.png'],
      isNull,
      reason:
          'A file in a subdirectory of a declared directory is on disk and not '
          'in the bundle. This is the rule the inspector exists to surface.',
    );
  });

  test('density variants attach to the asset and are not entries', () async {
    write('app/pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/images/
''');
    write('app/assets/images/logo.png', 'png');
    write('app/assets/images/2.0x/logo.png', 'png');
    write('app/assets/images/3.0x/logo.png', 'png');
    // Not a density directory, whatever it looks like.
    write('app/assets/images/dark/logo.png', 'png');

    var catalog = await resolve();

    expect(catalog.assets, hasLength(1));
    var logo = catalog.byKey['assets/images/logo.png']!;
    expect(logo.main.scale, isNull);
    expect(logo.main.key, 'assets/images/logo.png');
    expect(logo.variants.map((v) => v.scale), [2.0, 3.0]);
    expect(logo.variants.map((v) => v.key), [
      'assets/images/2.0x/logo.png',
      'assets/images/3.0x/logo.png',
    ]);
  });

  test('a shorthand density directory counts', () async {
    write('app/pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/images/logo.png
''');
    write('app/assets/images/logo.png', 'png');
    write('app/assets/images/3x/logo.png', 'png');

    var catalog = await resolve();

    expect(
      catalog.byKey['assets/images/logo.png']!.variants.map((v) => v.scale),
      [3.0],
      reason:
          "flutter_tools' own regex offers `plants/3x` as an example match, so "
          'the short form is a variant and not a stray directory.',
    );
  });

  test('a declaration can be a map with a path', () async {
    write('app/pubspec.yaml', '''
name: app
flutter:
  assets:
    - path: assets/heart.svg
''');
    write('app/assets/heart.svg', '<svg/>');

    var catalog = await resolve();

    expect(catalog.byKey.keys, ['assets/heart.svg']);
    expect(catalog.assets.single.declaration, 'assets/heart.svg');
  });

  test("a dependency's assets are keyed under packages/", () async {
    write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
''');
    write('dep/pubspec.yaml', '''
name: dep
flutter:
  assets:
    - assets/badge.png
''');
    write('dep/assets/badge.png', 'png');

    var catalog = await resolve();

    expect(catalog.byKey.keys, ['packages/dep/assets/badge.png']);
    var badge = catalog.assets.single;
    expect(badge.package, 'dep');
    expect(badge.packageRoot, depRoot());
  });

  test('a package in the config that nothing depends on stays out', () async {
    // The pub workspace case: one config resolves imports for every member, so
    // a sibling app is in the config and is not in this app's bundle.
    write('app/pubspec.yaml', 'name: app\n');
    write('dep/pubspec.yaml', '''
name: dep
flutter:
  assets:
    - assets/sibling.png
''');
    write('dep/assets/sibling.png', 'png');

    var catalog = await resolve();

    expect(
      catalog.assets,
      isEmpty,
      reason:
          'flutter_tools filters the config down to transitive dependencies '
          'for exactly this reason (asset.dart:423).',
    );
  });

  test('a dev-dependency is not in the bundle', () async {
    write('app/pubspec.yaml', '''
name: app
dev_dependencies:
  dep:
''');
    write('dep/pubspec.yaml', '''
name: dep
flutter:
  assets:
    - assets/test_only.png
''');
    write('dep/assets/test_only.png', 'png');

    var catalog = await resolve();

    expect(catalog.assets, isEmpty);
  });

  test('a dependency of a dependency is', () async {
    write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
''');
    write('dep/pubspec.yaml', '''
name: dep
dependencies:
  deep:
''');
    write('deep/pubspec.yaml', '''
name: deep
flutter:
  assets:
    - assets/buried.png
''');
    write('deep/assets/buried.png', 'png');

    var catalog = await resolve();

    expect(catalog.byKey.keys, ['packages/deep/assets/buried.png']);
  });

  test('fonts declare a family, and their files are assets too', () async {
    write('app/pubspec.yaml', '''
name: app
flutter:
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
        - asset: assets/fonts/Roboto-Bold.ttf
          weight: 700
        - asset: assets/fonts/Roboto-Italic.ttf
          style: italic
''');
    write('app/assets/fonts/Roboto-Regular.ttf', 'ttf');
    write('app/assets/fonts/Roboto-Bold.ttf', 'ttf');

    var catalog = await resolve();

    var family = catalog.fonts.single;
    expect(family.family, 'Roboto');
    expect(family.fonts.map((f) => f.weight), [null, 700]);
    expect(
      catalog.byKey.keys,
      containsAll([
        'assets/fonts/Roboto-Regular.ttf',
        'assets/fonts/Roboto-Bold.ttf',
      ]),
      reason: 'A font file is an asset key like any other.',
    );
    expect(catalog.assets.every((a) => a.isFont), isTrue);

    expect(
      catalog.problems.map((e) => e.kind),
      [AssetProblemKind.missingFontFile],
      reason:
          'The italic file is declared and absent. The family still resolves '
          'for its other two weights, which is what makes this easy to miss.',
    );
    expect(
      catalog.problems.single.declaration,
      'assets/fonts/Roboto-Italic.ttf',
    );
  });

  test('what is declared and missing is recorded, not skipped', () async {
    write('app/pubspec.yaml', '''
name: app
flutter:
  assets:
    - assets/missing.png
    - assets/nowhere/
    - assets/present.png
''');
    write('app/assets/present.png', 'png');

    var catalog = await resolve();

    expect(catalog.byKey.keys, ['assets/present.png']);
    expect(catalog.problems.map((e) => (e.kind, e.declaration)), [
      (AssetProblemKind.missingFile, 'assets/missing.png'),
      (AssetProblemKind.missingDirectory, 'assets/nowhere/'),
    ]);
  });

  test('an unparseable pubspec is reported against its package', () async {
    write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
''');
    write('dep/pubspec.yaml', 'name: dep\n  : not yaml at all\n');

    var catalog = await resolve();

    expect(catalog.problems.single.kind, AssetProblemKind.unreadablePubspec);
    expect(catalog.problems.single.package, 'dep');
  });

  test('the root package keeps its keys unprefixed', () async {
    write('app/pubspec.yaml', '''
name: app
flutter:
  uses-material-design: true
  assets:
    - assets/logo.png
''');
    write('app/assets/logo.png', 'png');

    var catalog = await resolve();

    expect(catalog.assets.single.key, 'assets/logo.png');
    expect(catalog.assets.single.package, isNull);
    expect(catalog.usesMaterialDesign, isTrue);
  });

  test("a packages/ declaration reaches into the dependency's lib", () async {
    // The documented way to bundle a file a dependency *has* but never
    // declared: `_resolveAsset` at asset.dart:1402 falls through to
    // `_resolvePackageAsset`, which reads `<name>`'s lib/.
    write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
flutter:
  assets:
    - packages/dep/images/logo.png
''');
    write('dep/pubspec.yaml', 'name: dep\n');
    write('dep/lib/images/logo.png', 'png');
    write('dep/lib/images/2.0x/logo.png', 'png');

    var catalog = await resolve();

    var logo = catalog.byKey['packages/dep/images/logo.png']!;
    expect(logo.package, isNull, reason: 'The root package declared it.');
    expect(logo.packageRoot, depRoot());
    expect(logo.main.path, p.join(depRoot(), 'lib', 'images', 'logo.png'));
    expect(logo.variants.map((v) => v.key), [
      'packages/dep/images/2.0x/logo.png',
    ]);
    expect(catalog.problems, isEmpty);
  });

  test(
    'a real file at the literal packages/ path wins over the reach',
    () async {
      // flutter_tools tries the declarer's own tree first, so a project with an
      // actual `packages/` directory keeps meaning its own files.
      write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
flutter:
  assets:
    - packages/dep/logo.png
''');
      write('dep/pubspec.yaml', 'name: dep\n');
      write('app/packages/dep/logo.png', 'the literal one');
      write('dep/lib/logo.png', 'the reached one');

      var catalog = await resolve();

      var logo = catalog.byKey['packages/dep/logo.png']!;
      expect(logo.main.path, p.join(appRoot(), 'packages', 'dep', 'logo.png'));
      expect(logo.packageRoot, appRoot());
    },
  );

  test('a packages/ declaration by a package is not re-prefixed', () async {
    write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
''');
    write('dep/pubspec.yaml', '''
name: dep
dependencies:
  deep:
flutter:
  assets:
    - packages/deep/icons/check.svg
''');
    write('deep/pubspec.yaml', 'name: deep\n');
    write('deep/lib/icons/check.svg', 'svg');

    var catalog = await resolve();

    expect(
      catalog.byKey.keys,
      ['packages/deep/icons/check.svg'],
      reason:
          'The declaration already names its package; '
          '"packages/dep/packages/deep/…" is a key nothing resolves.',
    );
  });

  test('a font asset can be a packages/ reach too', () async {
    write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
flutter:
  fonts:
    - family: Brand
      fonts:
        - asset: packages/dep/fonts/Brand-Regular.ttf
''');
    write('dep/pubspec.yaml', 'name: dep\n');
    write('dep/lib/fonts/Brand-Regular.ttf', 'ttf');

    var catalog = await resolve();

    var family = catalog.fonts.single;
    expect(family.family, 'Brand', reason: 'The root package declared it.');
    expect(family.fonts.single.key, 'packages/dep/fonts/Brand-Regular.ttf');
    expect(
      family.fonts.single.path,
      p.join(depRoot(), 'lib', 'fonts', 'Brand-Regular.ttf'),
    );
    var asset = catalog.byKey['packages/dep/fonts/Brand-Regular.ttf']!;
    expect(asset.packageRoot, depRoot());
    expect(catalog.problems, isEmpty);
  });

  test('a reach that lands nowhere is reported, and says why', () async {
    write('app/pubspec.yaml', '''
name: app
dependencies:
  dep:
flutter:
  assets:
    - packages/ghost/logo.png
    - packages/dep/absent.png
''');
    write('dep/pubspec.yaml', 'name: dep\n');

    var catalog = await resolve();

    expect(catalog.assets, isEmpty);
    var byDeclaration = {
      for (var problem in catalog.problems) problem.declaration: problem,
    };
    expect(
      byDeclaration['packages/ghost/logo.png']!.detail,
      contains('No package in the config'),
      reason:
          'The tool prints "Could not resolve package for asset" and fails '
          'the build on the same input.',
    );
    expect(
      byDeclaration['packages/dep/absent.png']!.detail,
      contains('Reaches into package "dep"'),
    );
    expect(catalog.problems.map((e) => e.kind).toSet(), {
      AssetProblemKind.missingFile,
    });
  });

  test('a transformed asset resolves, and says its bytes are wrong', () async {
    // A build runs `dart run <package> --input --output` over the file and
    // ships the result; the catalog serves the source bytes. Both facts are
    // reported: the asset resolves — the inspector can still show it — and
    // the problem says what a guest render of it is *not*.
    write('app/pubspec.yaml', '''
name: app
flutter:
  assets:
    - path: assets/icons/check.svg
      transformers:
        - package: vector_graphics_compiler
''');
    write('app/assets/icons/check.svg', '<svg/>');

    var catalog = await resolve();

    expect(catalog.byKey.keys, ['assets/icons/check.svg']);
    var problem = catalog.problems.single;
    expect(problem.kind, AssetProblemKind.unsupportedTransformer);
    expect(problem.declaration, 'assets/icons/check.svg');
    expect(problem.detail, contains('vector_graphics_compiler'));
  });

  group('parseScale', () {
    test('reads a density directory, long form and short', () {
      expect(AssetCatalog.parseScale('assets/2.0x/foo.png'), 2.0);
      expect(AssetCatalog.parseScale('assets/1.5x/foo.png'), 1.5);
      expect(AssetCatalog.parseScale('assets/3x/foo.png'), 3.0);
      expect(AssetCatalog.parseScale('3.0x/'), 3.0);
    });

    test('rejects what only looks like one', () {
      // `dark/` is the one the old overview report got wrong. There is no
      // theme variant in Flutter's asset resolution — only density.
      expect(AssetCatalog.parseScale('assets/dark/foo.png'), isNull);
      expect(AssetCatalog.parseScale('assets/foo.png'), isNull);
      // Narrower than flutter_tools, which suffix-matches this one.
      expect(AssetCatalog.parseScale('assets/foo2x/bar.png'), isNull);
    });
  });
}
