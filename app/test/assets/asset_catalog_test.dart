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
