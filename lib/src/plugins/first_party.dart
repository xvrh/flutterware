/// The first-party plugins, as a project declares them in
/// `tool/flutterware.dart`:
///
/// ```dart
/// const app = Pkg('packages/app');
///
/// void main() => Flutterware.configure((fw) {
///   fw.packages([app]);
///   fw.use(UiCatalog(packages: [.new(app, entrypoint: 'lib/catalog.dart')]));
/// });
/// ```
///
/// These carry identity and configuration only — the behaviour for each id is
/// compiled into the GUI. They live here, in the pure-Dart package, because the
/// config file runs under a plain `dart run` and cannot see the GUI.
library;

import 'package.dart';
import 'plugin.dart';

/// Pub dependencies, per declared package.
class Dependencies extends Plugin {
  Dependencies({this.packages = const [], String? label})
    : super('flutterware.dependencies', label: label ?? 'Dependencies');

  final List<DependenciesPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class DependenciesPackage extends PluginPackage {
  const DependenciesPackage(super.pkg);

  /// Every package — for plugins where per-package options are genuinely
  /// optional. Offered per plugin, never as a framework rule.
  static List<DependenciesPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) DependenciesPackage(pkg),
  ];
}

/// The UI catalog — entries rendered in the embedded engine.
class UiCatalog extends Plugin {
  UiCatalog({this.packages = const [], String? label})
    : super('flutterware.ui_catalog', label: label ?? 'UI catalog');

  final List<UiCatalogPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class UiCatalogPackage extends PluginPackage {
  const UiCatalogPackage(super.pkg, {this.entrypoint});

  /// Where this package declares its catalog entries; the plugin's convention
  /// applies when null.
  final String? entrypoint;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (entrypoint != null) 'entrypoint': entrypoint,
  };

  static List<UiCatalogPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) UiCatalogPackage(pkg),
  ];
}

/// The scenario runner.
class TestRunner extends Plugin {
  TestRunner({this.packages = const [], String? label})
    : super('flutterware.tests', label: label ?? 'Tests');

  final List<TestsPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class TestsPackage extends PluginPackage {
  const TestsPackage(super.pkg, {this.directory});

  /// Test directory relative to the package; `test` when null.
  final String? directory;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (directory != null) 'directory': directory,
  };

  static List<TestsPackage> each(List<Pkg> packages) => [
    for (var pkg in packages) TestsPackage(pkg),
  ];
}

/// The launcher-icon editor. Only meaningful for packages that are apps, so it
/// deliberately offers no `each` — naming them is the point.
class LauncherIcon extends Plugin {
  LauncherIcon({this.packages = const [], String? label})
    : super('flutterware.launcher_icon', label: label ?? 'Launcher icon');

  final List<LauncherIconPackage> packages;

  @override
  Map<String, Object?> get config => {
    'packages': [for (var p in packages) p.toJson()],
  };
}

class LauncherIconPackage extends PluginPackage {
  const LauncherIconPackage(super.pkg);
}
