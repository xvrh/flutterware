import 'package:flutterware/plugins.dart';

import 'authoring.dart';

export 'authoring.dart' show defaultCatalogRoot;

/// The plugin that owns the catalog. Everything else consumes it.
const previewsPluginId = 'flutterware.previews';

/// Where the catalog discovers preview entries, per package, as the previews
/// plugin declared it.
///
/// **One answer for the whole project, and that is the point.** The daemon's
/// address is a hash of its whole config, roots included, so two plugins asking
/// for different roots on the same package get two daemons compiling the same
/// files into two kernels. Measured on this repo before this existed: previews
/// declared `tool/catalog` and motion declared `tool/catalog/demos`, which cost
/// a second compiler, a second ~95MB warm kernel, and — because only one of
/// them was ever kept warm by use — a panel whose listing was current beside a
/// picture that was a version behind.
///
/// A plugin that *renders* through the catalog asks here. A plugin that scans
/// source files of its own keeps its own directory: they are different
/// questions, and conflating them is what caused the split.
Map<String, List<String>> catalogRootsFrom(PluginManifest manifest) {
  var roots = <String, List<String>>{};
  for (var declaration in manifest.plugins) {
    if (declaration.id != previewsPluginId) continue;
    for (var entry in (declaration.config['packages'] as List? ?? const [])) {
      if (entry is! Map) continue;
      var path = entry['path'];
      if (path is! String) continue;
      var directory = entry['directory'];
      roots[path] = [
        directory is String && directory.isNotEmpty
            ? directory
            : defaultCatalogRoot,
      ];
    }
  }
  return roots;
}
