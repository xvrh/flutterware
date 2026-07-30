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
      // Every `fw.use` in the config, in the order it was written — so a plugin
      // added to the repo's own config has to be added here too, which is the
      // point: this is the one test that runs that file.
      expect(manifest.plugins.map((p) => p.id), [
        'flutterware.dependencies',
        'flutterware.assets',
        'flutterware.ui_catalog',
      ]);
      var dependencies = manifest.plugins.firstWhere(
        (p) => p.id == 'flutterware.dependencies',
      );
      expect(dependencies.config['packages'], hasLength(3));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
