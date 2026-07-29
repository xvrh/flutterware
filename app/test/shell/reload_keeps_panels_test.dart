import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native/dependencies_plugin.dart';
import 'package:flutterware_app/src/plugins/native/registry.dart';
import 'package:flutterware_app/src/plugins/native/ui_catalog_plugin.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// The claim the whole projection diff exists to make, checked against the
/// **real** plugin classes rather than fakes.
///
/// `UiCatalogPlugin` holds a `CatalogSession` per package in `_sessions` — a
/// field of the *panel*, not of `UiCatalogCore` — and that session owns the
/// compile loop and the guest engine behind the texture. So the panel instance
/// surviving *is* the engine surviving: nothing needs to be booted to establish
/// it, because a field cannot outlive the object holding it.
///
/// The widget tests next door use `_FakeCore`, which is the right level for the
/// surfaces and the wrong level for this — a fake panel would prove that fakes
/// are reused.
String _manifest({String depsDir = 'app'}) =>
    '{"version":1,'
    '"packages":[{"path":"."},{"path":"app"},{"path":"examples/example"}],'
    '"plugins":['
    '{"id":"flutterware.dependencies","label":"Dependencies",'
    '"config":{"packages":[{"path":"$depsDir"}]}},'
    '{"id":"flutterware.ui_catalog","label":"UI catalog",'
    '"config":{"packages":[{"path":"examples/example"}]}}'
    ']}';

class _StubLoader implements ManifestLoader {
  _StubLoader(this.manifest);

  String manifest;

  @override
  Future<PluginManifest?> load(String path) async =>
      PluginManifest.parse(manifest);

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String path,
  ) async => (manifest: await load(path), error: null);

  @override
  String get dartExecutable => 'dart';
}

void main() {
  late String root;
  late _StubLoader loader;
  late ShellController shell;

  setUp(() async {
    // The real repo, so the declared packages exist on disk and the workspace
    // does not report them as typos.
    root = findRepoRoot('..')!;
    loader = _StubLoader(_manifest());
    shell = ShellController(
      appContext: AppContext(
        logger: LogClient.print(),
        appToolDirectory: Directory('.'),
      ),
      flutterSdk: FlutterSdkPath((await FlutterSdkPath.findSdks()).first.root),
      registry: buildNativeRegistry(),
      manifestLoader: loader,
      discovery: WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 0, 'worktree $root\nbranch refs/heads/main\n', ''),
      ),
    );
    await shell.start(root);
  });

  tearDown(() => shell.dispose());

  test('the real catalog panel survives an edit to another plugin', () async {
    var worktree = shell.selected!;
    var catalog =
        shell.sessionFor(worktree)!.pluginById('flutterware.ui_catalog')!
            as UiCatalogPlugin;
    var deps =
        shell.sessionFor(worktree)!.pluginById('flutterware.dependencies')!
            as DependenciesPlugin;

    // Only the Dependencies declaration moves.
    loader.manifest = _manifest(depsDir: 'examples/example');
    await shell.reloadConfig();

    var after = shell.sessionFor(worktree)!;
    expect(
      identical(after.pluginById('flutterware.ui_catalog'), catalog),
      isTrue,
      reason:
          'the catalog panel — and therefore every CatalogSession in its '
          '_sessions map, and therefore every guest engine — is untouched',
    );
    expect(
      identical(after.pluginById('flutterware.dependencies'), deps),
      isFalse,
      reason: 'the plugin whose declaration moved is rebuilt',
    );
    expect(shell.lastLoad(worktree)!.rebuilt, ['flutterware.dependencies']);
  });

  test('and dies when its own declaration moves', () async {
    var worktree = shell.selected!;
    var catalog = shell
        .sessionFor(worktree)!
        .pluginById('flutterware.ui_catalog');

    // The catalog's own `packages:` list, changed.
    loader.manifest =
        '{"version":1,'
        '"packages":[{"path":"."},{"path":"app"},{"path":"examples/example"}],'
        '"plugins":['
        '{"id":"flutterware.dependencies","label":"Dependencies",'
        '"config":{"packages":[{"path":"app"}]}},'
        '{"id":"flutterware.ui_catalog","label":"UI catalog",'
        '"config":{"packages":[{"path":"app"}]}}'
        ']}';
    await shell.reloadConfig();

    expect(
      identical(
        shell.sessionFor(worktree)!.pluginById('flutterware.ui_catalog'),
        catalog,
      ),
      isFalse,
      reason:
          'losing the device is the expected price of changing what it '
          'renders',
    );
  });

  test('a comment-only edit reaches neither plugin', () async {
    var worktree = shell.selected!;
    var before = shell.sessionFor(worktree)!.plugins;

    // A comment does not reach the manifest at all, so the config prints the
    // same bytes and the reload has nothing to do.
    await shell.reloadConfig();

    var after = shell.sessionFor(worktree)!.plugins;
    expect(identical(after[0], before[0]), isTrue);
    expect(identical(after[1], before[1]), isTrue);
  });
}
