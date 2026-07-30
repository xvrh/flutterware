import 'dart:io';

import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Executes this repo's real `tool/flutterware.dart`.
///
/// Heavy by the repo's convention — it spawns a Dart subprocess, which hangs
/// under `flutter test` but is fine here. Run with:
///
///     cd app && dart test integration_test/shell
///
/// **What is asserted is that the file runs and its output is coherent, not
/// what it happens to declare.** This used to pin the exact list of plugin ids,
/// with a comment saying that was the point — but the repo's own config is not
/// a fixture, it is configuration, and every change to it failed a test whose
/// subject is subprocess execution. The list is pinned where it belongs, in
/// `test/session/session_test.dart` and `test/session/mcp_server_test.dart`,
/// both of which read this same file through a `Session`.
void main() {
  test(
    'the repo config executes and its manifest decodes',
    () async {
      var root = findRepoRoot('..')!;
      // Not PATH's `dart`: this repo pins a newer SDK than the system one.
      var loader = ManifestLoader(dartExecutable: Platform.resolvedExecutable);

      var manifest = await loader.load(root);

      expect(manifest, isNotNull, reason: 'tool/flutterware.dart should exist');
      expect(manifest!.packages, isNotEmpty);
      expect(manifest.plugins, isNotEmpty);

      // A declared package that is not on disk is the one thing a config can
      // get wrong that nothing else notices — plugins filter unknown paths out,
      // so a typo silently means "this plugin does nothing".
      for (var package in manifest.packages) {
        expect(
          Directory(p.join(root, package.path)).existsSync(),
          isTrue,
          reason: 'declared package "${package.path}" is not on disk',
        );
      }

      var ids = manifest.plugins.map((plugin) => plugin.id).toList();
      expect(ids, everyElement(isNotEmpty));
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'two plugins declared with the same id would resolve to one',
      );

      // `path` is the join key the framework guarantees, and the only part of a
      // plugin's per-package config it understands. Every one of them has to
      // survive the subprocess and reach `manifest.packages`, which is what the
      // typo check and the shell's package rows are read off.
      //
      // This used to assert the reverse — that no plugin names a package the
      // config never declared — against a separate `fw.packages([...])` list.
      // That list is gone and the packages are read off these same entries, so
      // the old direction is now true by construction and worth nothing.
      var named = <String>{};
      for (var plugin in manifest.plugins) {
        var packages = plugin.config['packages'] as List? ?? const [];
        for (var entry in packages.cast<Map>()) {
          named.add(entry['path']! as String);
        }
      }
      expect(
        named,
        isNotEmpty,
        reason: 'no plugin declared any package, so nothing was cross-checked',
      );
      expect(
        manifest.packages.map((package) => package.path).toSet(),
        named,
        reason: 'a package a plugin names went missing between the two',
      );
      expect(
        manifest.packages.map((package) => package.path).toList(),
        hasLength(named.length),
        reason: 'a package named by two plugins should be reported once',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
