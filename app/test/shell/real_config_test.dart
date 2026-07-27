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
  test('a directory with no config walks up to the one that has it', () {
    var root = findRepoRoot('..');
    expect(root, isNotNull);
    expect(
      findRepoRoot('lib/src/shell'),
      root,
      reason: 'app/ declares no config of its own',
    );
  });

  test('a directory with its own config is its own root', () {
    // `examples/example` is both a workspace member of this repo and a project
    // in its own right — it has a `tool/flutterware.dart`. Opening it must give
    // you *its* config, not the monorepo's, or `dart run flutterware` inside a
    // nested app would silently open the wrong project.
    expect(findRepoRoot('../examples/example'), endsWith('examples/example'));
    expect(findRepoRoot('../examples/example'), isNot(findRepoRoot('..')));
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
    var report = dependencies.report;
    // The parent counts packages rather than summing their dependency counts,
    // which would double-count everything shared between them.
    expect(report.status.message, '3 packages');
    expect(report.children.map((c) => c.id), ['.', 'app', 'examples/example']);
    expect(report.children.map((c) => c.label), [
      'root',
      'app',
      'examples/example',
    ]);
    expect(report.children.every((c) => c.status.message == '—'), isTrue);
    expect(report.view.toText(), contains('not computed'));

    workspace.dispose();
  });
}
