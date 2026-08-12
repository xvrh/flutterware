import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../launcher_icon/model/role.dart';
import '../launcher_icon/model/scan.dart';
import 'stock_icons.dart';

/// The picture that stands for the open project — the user's own launcher icon,
/// resolved from what `tool/flutterware.dart` declared.
///
/// One window per repository, several at once, all identical: the thing that
/// tells them apart has to come from the project, and the only picture a
/// project already has is the icon it ships. So this reads it rather than
/// inventing a mark.
///
/// **Reuses the launcher-icon scan and nothing else of that plugin.** A project
/// does not have to declare `LauncherIcon` to have a window, so this calls
/// [scanIcons] directly — the plugin and this feature happen to read the same
/// files, which is not the same as one depending on the other.
class ProjectFace {
  const ProjectFace({
    required this.file,
    required this.role,
    required this.package,
  });

  /// The image on disk. Always a PNG: the roles below are chosen partly so it
  /// is, because `.ico` needs a decoder Flutter does not ship.
  final File file;

  /// Which platform's icon this came from, for saying so in a tooltip.
  final IconRole role;

  /// The package that was declared, for the same reason.
  final String package;
}

/// The face for [manifest]'s declared package, or null when there is none.
///
/// Null is an ordinary answer with several ordinary causes: the project
/// declared no identity, the package it named is not there, it has no launcher
/// icons yet, or every icon it has is still the template's. None of them is an
/// error and none is worth a log line — the result is a window that looks like
/// it did before, which is where every project starts.
ProjectFace? resolveProjectFace({
  required String worktreeRoot,
  required PluginManifest manifest,
}) {
  var declared = manifest.identity?.package;
  if (declared == null) return null;

  var packageRoot = p.normalize(p.join(worktreeRoot, declared.path));
  if (!Directory(packageRoot).existsSync()) return null;

  var scan = scanIcons(packageRoot: packageRoot, packagePath: declared.path);
  for (var role in faceRoles) {
    for (var found in scan.roles) {
      if (found.role != role || found.files.isEmpty) continue;
      // Sorted smallest first, so the last is the most pixels to work with.
      var file = File(found.files.last.absolutePath);
      if (!file.existsSync()) continue;
      // This role is still the template's, so the next one is worth a look —
      // a project that customised iOS but not macOS is ordinary.
      if (isStockIcon(file)) break;
      return ProjectFace(file: file, role: role, package: declared.path);
    }
  }
  return null;
}
