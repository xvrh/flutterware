import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

/// The picture that stands for the open project — the file
/// `tool/flutterware.dart` named.
///
/// One window per repository, several at once, all identical: the thing that
/// tells them apart has to come from the project, and the only picture a
/// project already has is the one it ships. So this reads it rather than
/// inventing a mark.
///
/// A path, not a search. This used to walk the declared package's platform
/// directories and take the largest icon that was not a `flutter create`
/// default, recognised by hashing against a list of template files. That list is
/// a promise about somebody else's repository, and it expired: a mobile app
/// whose generator writes iOS and Android icons and never touches `macos/` got
/// the Flutter logo in its Dock, because the template icon sitting in `macos/`
/// had been written by an older Flutter than the hashes were taken from. See
/// [ProjectIdentity.icon].
class ProjectFace {
  const ProjectFace({
    required this.file,
    required this.package,
    required this.icon,
  });

  /// The image on disk.
  final File file;

  /// The package that was declared, for saying so in a tooltip.
  final String package;

  /// The icon path that was declared, relative to [package] — the other half of
  /// that tooltip, and the thing to correct when the picture is wrong.
  final String icon;
}

/// The face [manifest] declared, or null when it declared none.
///
/// Null here means only *no identity in the config*, which is an ordinary
/// answer: the window looks like it did before, which is where every project
/// starts. A declaration that names a file which is not there is **not** this
/// function's null — it is [projectFaceProblem], reported against the worktree,
/// because a path somebody typed is worth a sentence rather than a shrug.
ProjectFace? resolveProjectFace({
  required String worktreeRoot,
  required PluginManifest manifest,
}) {
  var identity = manifest.identity;
  if (identity == null) return null;

  var file = File(projectFacePath(worktreeRoot, identity));
  if (!file.existsSync()) return null;

  return ProjectFace(
    file: file,
    package: identity.package.path,
    icon: identity.icon,
  );
}

/// Where [identity] says its picture is.
String projectFacePath(String worktreeRoot, ProjectIdentity identity) =>
    p.normalize(p.join(worktreeRoot, identity.package.path, identity.icon));

/// What is wrong with [manifest]'s declared icon, or null when nothing is.
///
/// Run at config load rather than when the chip is drawn: the two ways to get
/// this wrong — a typo in the path, and an image format Flutter has no decoder
/// for — both look identical from the chip's side, which is a window with no
/// chip and no reason given. That is the failure this whole field exists to stop
/// happening.
String? projectFaceProblem({
  required String worktreeRoot,
  required PluginManifest manifest,
}) {
  var identity = manifest.identity;
  if (identity == null) return null;

  var declared = p.join(identity.package.path, identity.icon);
  if (!File(projectFacePath(worktreeRoot, identity)).existsSync()) {
    return 'Declared identity icon not found: $declared';
  }
  var extension = p.extension(identity.icon).toLowerCase();
  if (!_decodable.contains(extension)) {
    return 'Declared identity icon $declared is a $extension, which Flutter '
        'cannot decode. Point it at one of: ${_decodable.join(', ')}.';
  }
  return null;
}

/// The formats Flutter's own image codecs read. `.ico` and `.svg` are the two
/// that get declared anyway — a Windows launcher icon and a logo — and both
/// would reach the chip as an empty box.
const _decodable = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};
