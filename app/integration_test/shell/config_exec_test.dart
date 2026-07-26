import 'dart:io';

import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';
import 'package:test/test.dart';

/// Executes this repo's real `tool/flutterware.dart`.
///
/// Heavy by the repo's convention — it spawns a Dart subprocess, which hangs
/// under `flutter test` but is fine here. Run with:
///
///     cd app && dart test integration_test/shell
void main() {
  test(
    'the repo config emits the workspace manifest',
    () async {
      var root = findRepoRoot('..')!;
      // Not PATH's `dart`: this repo pins a newer SDK than the system one.
      var loader = ManifestLoader(dartExecutable: Platform.resolvedExecutable);

      var manifest = await loader.load(root);

      expect(manifest, isNotNull, reason: 'tool/flutterware.dart should exist');
      expect(manifest!.packages.map((p) => p.path), [
        '.',
        'app',
        'examples/example',
      ]);
      expect(manifest.packages.first.tags, ['lib']);
      expect(manifest.plugins.single.id, 'flutterware.dependencies');
      var declared = manifest.plugins.single.config['packages']! as List;
      expect(declared, hasLength(3));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
