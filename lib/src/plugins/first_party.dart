/// The first-party plugins, as a project declares them in
/// `tool/flutterware.dart`:
///
/// ```dart
/// void main() => Flutterware.configure((fw) => fw
///   ..use(Dependencies())
///   ..use(UiCatalog()));
/// ```
///
/// These carry identity and configuration only — the behaviour for each id is
/// compiled into the GUI. They live here, in the pure-Dart package, because the
/// config file runs under a plain `dart run` and cannot see the GUI.
library;

import 'plugin.dart';

/// Pub dependencies: what the project depends on, and what depends on what.
class Dependencies extends Plugin {
  Dependencies({String? label})
    : super('flutterware.dependencies', label: label ?? 'Dependencies');
}

/// The UI catalog — entries rendered in the embedded engine.
class UiCatalog extends Plugin {
  UiCatalog({String? label})
    : super('flutterware.ui_catalog', label: label ?? 'UI catalog');
}

/// The scenario runner.
class TestRunner extends Plugin {
  TestRunner({String? label})
    : super('flutterware.tests', label: label ?? 'Tests');
}

/// The launcher-icon editor.
class LauncherIcon extends Plugin {
  LauncherIcon({String? label})
    : super('flutterware.launcher_icon', label: label ?? 'Launcher icon');
}
