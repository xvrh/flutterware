import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/identity/project_face.dart';
import 'package:path/path.dart' as p;

/// Resolving the picture that stands for a project.
///
/// Against this repository rather than a fixture tree, deliberately: `app`
/// declares a real icon at a real path, which is the case worth testing against
/// something that would notice if the file moved.
void main() {
  /// The repo root, from `app/` where these tests run.
  var repoRoot = p.normalize(p.join(Directory.current.path, '..'));

  const appIcon =
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png';

  PluginManifest declaring(String package, String icon) => PluginManifest(
    const [],
    identity: ProjectIdentity(package: Pkg(package), icon: icon),
  );

  test('the declared icon is the face', () {
    var face = resolveProjectFace(
      worktreeRoot: repoRoot,
      manifest: declaring('app', appIcon),
    );
    expect(face, isNotNull);
    expect(face!.package, 'app');
    expect(face.icon, appIcon);
    expect(face.file.existsSync(), isTrue);
    expect(p.basename(face.file.path), 'app_icon_1024.png');
  });

  test('a project that declares nothing has no face', () {
    expect(
      resolveProjectFace(
        worktreeRoot: repoRoot,
        manifest: const PluginManifest([]),
      ),
      isNull,
    );
    expect(
      projectFaceProblem(
        worktreeRoot: repoRoot,
        manifest: const PluginManifest([]),
      ),
      isNull,
    );
  });

  /// The case the whole shape of this exists for: a path somebody typed and got
  /// wrong is a sentence, not a window that quietly looks like every other one.
  test('an icon that is not there is reported, not passed over', () {
    var manifest = declaring('app', 'assets/nope.png');
    expect(
      resolveProjectFace(worktreeRoot: repoRoot, manifest: manifest),
      isNull,
    );
    expect(
      projectFaceProblem(worktreeRoot: repoRoot, manifest: manifest),
      allOf(contains('not found'), contains('app/assets/nope.png')),
    );
  });

  test('a package that is not there is reported through its icon path', () {
    var manifest = declaring('packages/not_here', 'logo.png');
    expect(
      resolveProjectFace(worktreeRoot: repoRoot, manifest: manifest),
      isNull,
    );
    expect(
      projectFaceProblem(worktreeRoot: repoRoot, manifest: manifest),
      contains('packages/not_here/logo.png'),
    );
  });

  /// `windows.ico` is the one a project reaches for and Flutter cannot read.
  /// It exists, so the existence check passes and only this catches it.
  test('a format Flutter cannot decode is reported', () {
    const ico = 'windows/runner/resources/app_icon.ico';
    expect(
      File(p.join(repoRoot, 'app', ico)).existsSync(),
      isTrue,
      reason: 'this test needs a real .ico to point at',
    );
    expect(
      projectFaceProblem(
        worktreeRoot: repoRoot,
        manifest: declaring('app', ico),
      ),
      allOf(contains('.ico'), contains('cannot decode')),
    );
  });
}
