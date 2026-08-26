import 'package:flutterware_app/src/assets/model/asset_catalog.dart';
import 'package:flutterware_app/src/assets/model/asset_tree.dart';
import 'package:test/test.dart';

/// The folding, without a widget in sight.
///
/// Every asset here carries its own byte length, so nothing in this file
/// touches a disk — which is also what lets the tree be asserted on at the
/// grain it is built at rather than through whatever a row happens to print.
void main() {
  AssetFile file(String key, {double? scale, int length = 400}) =>
      AssetFile(path: '/project/$key', key: key, scale: scale, length: length);

  ResolvedAsset asset(String key, {List<AssetFile>? files}) => ResolvedAsset(
    key: key,
    package: null,
    packageRoot: '/project',
    declaration: key,
    files: files ?? [file(key)],
  );

  List<String> namesOf(AssetNode node) => [
    for (var child in node.sortedChildren) child.name,
  ];

  AssetNode childNamed(AssetNode node, String name) =>
      node.sortedChildren.firstWhere((child) => child.name == name);

  test('folds keys into the directories that hold them', () {
    var tree = AssetTree.of([
      asset('assets/images/logo.png'),
      asset('assets/images/hero.png'),
      asset('assets/i18n/en.json'),
    ]);

    expect(tree.prefix, 'assets');
    expect(namesOf(tree.root), ['i18n', 'images']);
    expect(childNamed(tree.root, 'images').sortedAssets.map((a) => a.key), [
      'assets/images/hero.png',
      'assets/images/logo.png',
    ]);
  });

  test('collapses a chain of single-child directories into one row', () {
    var tree = AssetTree.of([
      asset('assets/images/logo.png'),
      asset('assets/images/illustrations/onboarding/step-one.png'),
      asset('assets/images/illustrations/onboarding/step-two.png'),
    ]);

    expect(namesOf(tree.root), ['illustrations/onboarding']);
    expect(
      childNamed(tree.root, 'illustrations/onboarding').totalCount,
      2,
      reason: 'The collapse merges labels, never the contents.',
    );
    expect(
      tree.prefix,
      'assets/images',
      reason: 'Nothing branches above `images`, so no row is spent on it.',
    );
  });

  test('a lone asset folds its whole directory into the prefix', () {
    var tree = AssetTree.of([asset('assets/images/logo.png')]);

    expect(tree.prefix, 'assets/images');
    expect(namesOf(tree.root), isEmpty);
    expect(tree.root.sortedAssets.single.key, 'assets/images/logo.png');
  });

  test('counts and bytes roll up through every level', () {
    var tree = AssetTree.of([
      asset('assets/images/logo.png', files: [file('assets/images/logo.png')]),
      asset(
        'assets/images/deep/one.png',
        files: [file('assets/images/deep/one.png', length: 100)],
      ),
      asset(
        'assets/images/deep/two.png',
        files: [file('assets/images/deep/two.png', length: 250)],
      ),
    ]);

    expect(tree.prefix, 'assets/images');
    expect(tree.root.totalCount, 3);
    expect(tree.root.totalBytes, 750);

    var deep = childNamed(tree.root, 'deep');
    expect(deep.totalCount, 2);
    expect(deep.totalBytes, 350);
  });

  test('a density directory never becomes a row', () {
    var tree = AssetTree.of([
      asset(
        'assets/images/logo.png',
        files: [
          file('assets/images/logo.png', length: 100),
          file('assets/images/2.0x/logo.png', scale: 2, length: 200),
          file('assets/images/3.0x/logo.png', scale: 3, length: 300),
        ],
      ),
      asset('assets/images/hero.png', files: [file('assets/images/hero.png')]),
    ]);

    expect(
      namesOf(tree.root),
      isEmpty,
      reason:
          'The variants live on the asset, not beside it. A tree grown from '
          'file paths would show a `2.0x` folder that is in no bundle.',
    );
    expect(tree.root.totalCount, 2);
    expect(
      tree.root.totalBytes,
      1000,
      reason: 'Variant bytes ship, so they count.',
    );
  });

  test('a key with no directory sits at the root', () {
    var tree = AssetTree.of([
      asset('config.json'),
      asset('assets/images/logo.png'),
    ]);

    expect(tree.prefix, isEmpty, reason: 'Nothing is shared to fold off.');
    expect(tree.root.sortedAssets.single.key, 'config.json');
    expect(namesOf(tree.root), ['assets/images']);
  });

  test('a dependency section folds its packages/ prefix off too', () {
    var tree = AssetTree.of([
      asset('packages/brand/assets/mark.png'),
      asset('packages/brand/assets/icons/tick.svg'),
    ]);

    expect(tree.prefix, 'packages/brand/assets');
    expect(namesOf(tree.root), ['icons']);
  });

  test('an empty bundle is an empty tree', () {
    var tree = AssetTree.of([]);

    expect(tree.isEmpty, isTrue);
    expect(tree.prefix, isEmpty);
  });

  group('the folder sheet', () {
    test('shows everything beneath the folder, headed by directory', () {
      var tree = AssetTree.of([
        asset('assets/images/logo.png'),
        asset('assets/images/icons/star.png'),
        asset('assets/images/deep/down/here.png'),
      ]);

      var sections = assetSheetSections(tree.root);

      expect(
        sections.map((s) => s.label),
        ['deep/down', 'icons', ''],
        reason:
            'Each directory before the ones inside it, and the assets sitting '
            'loose in the folder last under no heading.',
      );
      expect(
        sections.last.assets.single.key,
        'assets/images/logo.png',
        reason: 'A sheet of a folder is not a sheet of doors into it.',
      );
    });

    test('a heading is the whole path down to its assets', () {
      var tree = AssetTree.of([
        asset('assets/a.png'),
        asset('assets/one/two/three/b.png'),
      ]);

      expect(
        assetSheetSections(tree.root).first.label,
        'one/two/three',
        reason:
            'A grid has no indentation to nest with, so the heading carries '
            'the path instead.',
      );
    });

    test('a heading knows the place it names', () {
      var tree = AssetTree.of([
        asset('assets/images/logo.png'),
        asset('assets/i18n/en.json'),
      ]);

      expect(
        assetSheetSections(tree.root).map((s) => s.path),
        containsAll(['assets/i18n', 'assets/images']),
        reason: 'A heading that names a place has to be able to go there.',
      );
    });

    test('an empty folder has no sections at all', () {
      expect(assetSheetSections(AssetTree.of([]).root), isEmpty);
    });
  });

  test('names sort the way a reader scans them, not by case', () {
    var tree = AssetTree.of([
      asset('assets/data/zebra.json'),
      asset('assets/data/README.md'),
      asset('assets/data/apple.json'),
    ]);

    expect(
      assetSheetSections(tree.root).single.assets.map((a) => a.key),
      [
        'assets/data/apple.json',
        'assets/data/README.md',
        'assets/data/zebra.json',
      ],
      reason:
          'Case-insensitive, so `README.md` sits among its neighbours instead '
          'of above every lowercase name — the rule the changes tree uses, '
          'shared so two trees in one window do not disagree about it.',
    );
  });
}
