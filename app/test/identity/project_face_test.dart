import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/identity/project_face.dart';
import 'package:flutterware_app/src/launcher_icon/model/role.dart';
import 'package:path/path.dart' as p;

/// Resolving the picture that stands for a project.
///
/// Against this repository rather than a fixture tree, deliberately: it holds
/// both cases the resolver has to tell apart — `app` has a real icon, and
/// `examples/example` is an untouched `flutter create` project whose icons are
/// still the template's. A fixture would have to *contain a copy of* the
/// template icons to test the second case, and a copy that drifts is worse than
/// no test.
void main() {
  /// The repo root, from `app/` where these tests run.
  var repoRoot = p.normalize(p.join(Directory.current.path, '..'));

  PluginManifest declaring(String? package) => PluginManifest(
    const [],
    identity: package == null ? null : ProjectIdentity(package: Pkg(package)),
  );

  test("the declared package's own icon is the face", () {
    var face = resolveProjectFace(
      worktreeRoot: repoRoot,
      manifest: declaring('app'),
    );
    expect(face, isNotNull);
    expect(face!.package, 'app');
    // macOS is first in preference and this package has one.
    expect(face.role, IconRole.macosApp);
    expect(face.file.existsSync(), isTrue);
    expect(p.basename(face.file.path), 'app_icon_1024.png');
  });

  test('a project that declares nothing has no face', () {
    expect(
      resolveProjectFace(worktreeRoot: repoRoot, manifest: declaring(null)),
      isNull,
    );
  });

  test('a declared package that is not there has no face', () {
    expect(
      resolveProjectFace(
        worktreeRoot: repoRoot,
        manifest: declaring('packages/not_here'),
      ),
      isNull,
    );
  });

  /// The case that makes the feature worth having: without this, every
  /// untouched project in the Dock shows the same blue bird.
  test('a package still carrying the Flutter default has no face', () {
    var face = resolveProjectFace(
      worktreeRoot: repoRoot,
      manifest: declaring('examples/example'),
    );
    expect(
      face,
      isNull,
      reason:
          'examples/example is a stock flutter create project. If this fails, '
          'either it grew a real icon — fine, point this test elsewhere — or '
          'Flutter changed its template and the hashes in project_face.dart '
          'need refreshing.',
    );
  });
}
