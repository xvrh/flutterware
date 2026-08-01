import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds the `package_config.json` that resolves [packageRoot]'s imports.
///
/// Walking up rather than looking in [packageRoot] is not a convenience: in a
/// pub **workspace** only the root has a `.dart_tool/`, so a member package —
/// `examples/example` here — has no config of its own and resolving from its
/// own directory finds nothing.
///
/// The config the catalog needs is whichever one resolves *all three* of
/// `package:flutter`, `package:flutterware` and the demos' own package. That is
/// the project's, not the GUI's: a user's project depends on flutterware, so
/// its config covers everything, while the GUI's copy under `~/.flutterware/`
/// has never heard of the user's package.
String? findPackageConfig(String packageRoot) {
  for (var dir = p.absolute(packageRoot); ; dir = p.dirname(dir)) {
    var candidate = p.join(dir, '.dart_tool', 'package_config.json');
    if (File(candidate).existsSync()) return candidate;
    if (p.dirname(dir) == dir) return null;
  }
}

/// Like [findPackageConfig], but says what it looked for when it fails —
/// otherwise the symptom is a compile error about `package:flutter` that reads
/// as a broken SDK.
String requirePackageConfig(String packageRoot) =>
    findPackageConfig(packageRoot) ??
    (throw StateError(
      'No .dart_tool/package_config.json above "$packageRoot". '
      'Run `dart pub get` in that project first.',
    ));
