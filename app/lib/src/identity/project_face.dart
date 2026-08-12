import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../launcher_icon/model/role.dart';
import '../launcher_icon/model/scan.dart';

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

/// Roles worth showing, best first.
///
/// Ordered by how large and how square the art tends to be, not by platform
/// importance: macOS ships 1024px, iOS 1024px, web 512px, Android's densest
/// mipmap is usually 192px. `windows.ico` is deliberately absent — it is the
/// one role whose file Flutter cannot decode.
const _preferredRoles = [
  IconRole.macosApp,
  IconRole.iosApp,
  IconRole.webIcon,
  IconRole.androidLegacy,
];

/// SHA-1 of the icons `flutter create` writes, per platform.
///
/// **A project whose icon is still the Flutter default has no face**, and
/// saying so is the point: three untouched projects would otherwise be three
/// windows showing the same blue bird, which is exactly the confusion this
/// feature exists to remove. Colour cannot rescue it either — it would be
/// derived from the same shared image.
///
/// Hashes rather than a heuristic, because the question is literally "is this
/// byte-for-byte the file the template ships". They go stale when Flutter
/// changes its template, and the failure when they do is the old behaviour —
/// a window showing the default icon — not a crash.
const _stockIcons = {
  '7b0546f328068d8701df0cb849f6f1106edab1e8', // ios, 1024
  '6ae2aa59ecf8ab9341dbaaf8cc6b4a0bebbd487f', // macos, 1024
  'dd0452802ca0cd6c81b9b5982aeb56b051b73829', // android, xxxhdpi
  'b3fc122b12b47f9925deaf8158a8e630b610d622', // web, 512
};

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
  for (var role in _preferredRoles) {
    for (var found in scan.roles) {
      if (found.role != role || found.files.isEmpty) continue;
      // Sorted smallest first, so the last is the most pixels to work with.
      var file = File(found.files.last.absolutePath);
      if (!file.existsSync()) continue;
      // This role is still the template's, so the next one is worth a look —
      // a project that customised iOS but not macOS is ordinary.
      if (_isStock(file)) break;
      return ProjectFace(file: file, role: role, package: declared.path);
    }
  }
  return null;
}

bool _isStock(File file) {
  try {
    return _stockIcons.contains(
      sha1.convert(file.readAsBytesSync()).toString(),
    );
  } on IOException {
    return false;
  }
}
