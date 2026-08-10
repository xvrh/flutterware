import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native/registry.dart';
import 'package:flutterware_app/src/shell/config_load.dart';
import 'package:flutterware_app/src/shell/repo_layout.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// The one claim the reload has to make, checked against the **real** plugin
/// classes rather than fakes.
///
/// A config that changed rebuilds everything, and losing a compiled catalog to
/// that is the accepted price. A config that did *not* change must cost nothing
/// — and `PreviewsPlugin` holds a `CatalogSession` per package, so "nothing" is
/// worth thousands of milliseconds here.
///
/// The widget tests next door use a fake core, which is the right level for the
/// surfaces and the wrong level for this: reusing a fake proves fakes are
/// reused.
String _manifest({String depsDir = 'app'}) =>
    '{"version":1,'
    '"packages":[{"path":"."},{"path":"app"},{"path":"examples/example"}],'
    '"plugins":['
    '{"id":"flutterware.dependencies","label":"Dependencies",'
    '"config":{"packages":[{"path":"$depsDir"}]}},'
    '{"id":"flutterware.previews","label":"Previews",'
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

  @override
  Duration get timeout => Duration.zero; // Unused: no stub spawns a process.
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

  test('a config that declares the same thing costs nothing', () async {
    var worktree = shell.selected!;
    var session = shell.sessionFor(worktree)!;
    var before = session.plugins;

    // What a comment, a reformat or a save-all produces: the config runs and
    // prints exactly what it printed before.
    await shell.reloadConfig();

    expect(identical(shell.sessionFor(worktree), session), isTrue);
    expect(
      identical(shell.sessionFor(worktree)!.plugins[0], before[0]),
      isTrue,
    );
    expect(
      identical(shell.sessionFor(worktree)!.plugins[1], before[1]),
      isTrue,
    );
    expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.unchanged);
  });

  test('and a config that declares something else rebuilds', () async {
    var worktree = shell.selected!;
    var before = shell.sessionFor(worktree)!.plugins.first;

    loader.manifest = _manifest(depsDir: 'examples/example');
    await shell.reloadConfig();

    expect(
      identical(shell.sessionFor(worktree)!.plugins.first, before),
      isFalse,
    );
    expect(shell.lastLoad(worktree)!.outcome, ConfigLoadOutcome.rebuilt);
  });
}
