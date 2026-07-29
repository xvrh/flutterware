import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/plugins/manifest_diff.dart';

PluginManifest _m(
  List<PluginDeclaration> plugins, {
  List<Pkg> packages = const [Pkg('.')],
}) => PluginManifest(plugins, packages: packages);

const _one = PluginDeclaration(id: 'a.one', label: 'One');
const _two = PluginDeclaration(id: 'a.two', label: 'Two');

void main() {
  test('identical manifests produce an empty diff', () {
    var diff = ManifestDiff.between(_m([_one]), _m([_one]));
    expect(diff.isEmpty, isTrue);
    expect(diff.needsFullRebuild, isFalse);
    expect(diff.affected, isEmpty);
  });

  test('a changed config key is named, and only that plugin is affected', () {
    var before = _m([
      _one,
      const PluginDeclaration(
        id: 'a.two',
        label: 'Two',
        config: {'dir': 'test'},
      ),
    ]);
    var after = _m([
      _one,
      const PluginDeclaration(
        id: 'a.two',
        label: 'Two',
        config: {'dir': 'test/unit'},
      ),
    ]);

    var diff = ManifestDiff.between(before, after);
    expect(diff.changed, {
      'a.two': ['dir'],
    });
    expect(diff.added, isEmpty);
    expect(diff.removed, isEmpty);
    expect(diff.affected, ['a.two']);
  });

  test('an added and a dropped config key are both named', () {
    var diff = ManifestDiff.between(
      _m([
        const PluginDeclaration(
          id: 'a.one',
          label: 'One',
          config: {'kept': 1, 'gone': 2},
        ),
      ]),
      _m([
        const PluginDeclaration(
          id: 'a.one',
          label: 'One',
          config: {'kept': 1, 'fresh': 3},
        ),
      ]),
    );
    expect(diff.changed['a.one'], ['fresh', 'gone']);
  });

  test('a changed label counts as a change, named as `label`', () {
    var diff = ManifestDiff.between(
      _m([_one]),
      _m([const PluginDeclaration(id: 'a.one', label: 'Uno')]),
    );
    expect(diff.changed, {
      'a.one': ['label'],
    });
  });

  test('nested config is compared deeply, not by reference', () {
    var before = _m([
      const PluginDeclaration(
        id: 'a.one',
        label: 'One',
        config: {
          'packages': [
            {'path': 'app'},
          ],
        },
      ),
    ]);
    var after = _m([
      const PluginDeclaration(
        id: 'a.one',
        label: 'One',
        config: {
          'packages': [
            {'path': 'app'},
          ],
        },
      ),
    ]);
    expect(ManifestDiff.between(before, after).isEmpty, isTrue);
  });

  test('a nested change is caught and named by its top-level key', () {
    var before = _m([
      const PluginDeclaration(
        id: 'a.one',
        label: 'One',
        config: {
          'packages': [
            {'path': 'app'},
          ],
        },
      ),
    ]);
    var after = _m([
      const PluginDeclaration(
        id: 'a.one',
        label: 'One',
        config: {
          'packages': [
            {'path': 'app'},
            {'path': 'web'},
          ],
        },
      ),
    ]);
    expect(ManifestDiff.between(before, after).changed, {
      'a.one': ['packages'],
    });
  });

  test('added and removed plugins are reported separately', () {
    var diff = ManifestDiff.between(_m([_one]), _m([_one, _two]));
    expect(diff.added, ['a.two']);
    expect(diff.removed, isEmpty);
    expect(diff.affected, ['a.two']);

    var back = ManifestDiff.between(_m([_one, _two]), _m([_one]));
    expect(back.added, isEmpty);
    expect(back.removed, ['a.two']);
  });

  test('a changed packages list forces a full rebuild', () {
    var diff = ManifestDiff.between(
      _m([_one]),
      _m([_one], packages: [const Pkg('.'), const Pkg('app')]),
    );
    expect(diff.needsFullRebuild, isTrue);
    expect(diff.isEmpty, isFalse);
  });

  test('a package changing only its tags still forces a full rebuild', () {
    var diff = ManifestDiff.between(
      _m([_one], packages: [const Pkg('app')]),
      _m(
        [_one],
        packages: [
          const Pkg('app', tags: ['gui']),
        ],
      ),
    );
    expect(diff.needsFullRebuild, isTrue);
  });

  test('reordering rebuilds nothing but is not empty', () {
    var diff = ManifestDiff.between(_m([_one, _two]), _m([_two, _one]));
    expect(diff.orderChanged, isTrue);
    expect(diff.affected, isEmpty);
    expect(diff.isEmpty, isFalse);
  });

  test('adding a plugin is not also reported as a reorder', () {
    var diff = ManifestDiff.between(_m([_one]), _m([_one, _two]));
    expect(diff.orderChanged, isFalse);
  });

  test('duplicate ids are rejected rather than silently collapsed', () {
    expect(
      () => ManifestDiff.between(_m([_one]), _m([_one, _one])),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('summary names what moved, for the reload log', () {
    var diff = ManifestDiff.between(
      _m([
        _one,
        const PluginDeclaration(
          id: 'a.two',
          label: 'Two',
          config: {'dir': 'test'},
        ),
      ]),
      _m([
        _one,
        const PluginDeclaration(
          id: 'a.two',
          label: 'Two',
          config: {'dir': 'unit'},
        ),
      ]),
    );
    expect(diff.reasonFor('a.two'), 'dir changed');
    expect(diff.reasonFor('a.one'), isNull);
  });
}
