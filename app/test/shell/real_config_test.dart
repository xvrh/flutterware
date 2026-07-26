import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/dependencies_plugin.dart';
import 'package:flutterware_app/src/plugins/native/registry.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// End to end against this repo's own `tool/flutterware.dart`, with no stubs.
///
/// This is the case M1 got wrong: launching inside `examples/example` walked no
/// further, matched no worktree, fell back to the repo root, and found no
/// config — an empty sidebar with a tab named after the repo branch.
void main() {
  test('walking up from a subdirectory finds the repo root', () {
    var fromExample = findRepoRoot('../examples/example');
    var fromAppLib = findRepoRoot('lib/src/shell');
    expect(fromExample, isNotNull);
    expect(fromAppLib, fromExample);
    // The root is where the config lives.
    expect(
      findRepoRoot('..'),
      fromExample,
      reason: 'every subdirectory of the repo resolves to the same root',
    );
  });

  test('discovery reads the workspace members', () {
    var root = findRepoRoot('..')!;
    expect(
      discoverPackages(root),
      containsAll(['.', 'app', 'examples/example']),
    );
  });

  test('a declared manifest resolves to a working, idle plugin', () {
    var root = findRepoRoot('..')!;
    // The shape this repo's config emits — executing it is covered by
    // integration_test/shell/config_exec_test.dart.
    var manifest = PluginManifest.parse(
      '{"version":1,'
      '"packages":[{"path":"."},{"path":"app"},{"path":"examples/example"}],'
      '"plugins":[{"id":"flutterware.dependencies","label":"Dependencies",'
      '"config":{"packages":[{"path":"."},{"path":"app"},'
      '{"path":"examples/example"}]}}]}',
    );

    var workspace = Workspace(
      root: root,
      declared: manifest.packages,
      discovered: discoverPackages(root),
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/tmp/flutter'),
    );
    expect(workspace.unknownDeclarations, isEmpty);

    var plugins = buildNativeRegistry().resolve(
      manifest,
      const Worktree(path: '/repo', branch: 'main'),
      workspace,
    );
    var dependencies = plugins.whereType<DependenciesPlugin>().single;
    expect(dependencies.packages, ['.', 'app', 'examples/example']);

    // The laziness rule: constructing the plugin and reading its report must
    // not have started any work.
    expect(workspace.isRealised('.'), isFalse);
    expect(dependencies.report.status.message, '—');
    expect(dependencies.report.view.toText(), contains('not computed'));

    workspace.dispose();
  });
}
