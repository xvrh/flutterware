import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

/// The packages a manifest reports come off the plugins that name them.
///
/// This used to be a separate `fw.packages([...])` call, and the host filtered
/// each plugin's packages against it. A package the list forgot was dropped
/// from the plugin that had been configured with it, without a word — so the
/// list's only observable effect was to contradict the config below it.
void main() {
  const root = Pkg('.');
  const app = Pkg('app');

  /// A config, emitted and parsed back — the host reads this off a
  /// subprocess's stdout and never sees the objects.
  PluginManifest manifestOf(List<Plugin> plugins) {
    late String emitted;
    Flutterware.configure((fw) {
      for (var plugin in plugins) {
        fw.use(plugin);
      }
    }, emit: (line) => emitted = line);
    return PluginManifest.parse(emitted);
  }

  test('every package a plugin names is reported', () {
    var manifest = manifestOf([
      Dependencies(packages: DependenciesPackage.each([root, app])),
    ]);
    expect(manifest.packages.map((p) => p.path), ['.', 'app']);
  });

  test('a package named by several plugins is reported once', () {
    var manifest = manifestOf([
      Dependencies(packages: DependenciesPackage.each([root, app])),
      Assets(packages: AssetsPackage.each([app, root])),
    ]);
    expect(manifest.packages.map((p) => p.path), ['.', 'app']);
  });

  test('order follows the plugins, not the alphabet', () {
    var manifest = manifestOf([
      Assets(packages: AssetsPackage.each([app, root])),
    ]);
    expect(manifest.packages.map((p) => p.path), ['app', '.']);
  });

  test('a plugin with no packages contributes none', () {
    expect(manifestOf([Dependencies()]).packages, isEmpty);
    expect(manifestOf([]).packages, isEmpty);
  });

  test("a plugin's own per-package options are untouched", () {
    var manifest = manifestOf([
      UiCatalog(packages: [UiCatalogPackage(app, entrypoint: 'tool/catalog')]),
    ]);
    expect(manifest.packages.map((p) => p.path), ['app']);
    expect(manifest.plugins.single.config['packages'], [
      {'path': 'app', 'entrypoint': 'tool/catalog'},
    ]);
  });
}
