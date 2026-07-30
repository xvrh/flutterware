import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/dependencies_plugin.dart';
import 'package:flutterware_app/src/plugins/native/registry.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// Prints what `fw` would print, for this repo, so we can judge whether the
/// text projection is worth reading before designing a CLI around it.
///
///     cd app && flutter test test/tools/projection_dump_test.dart
///
/// Superseded by `dart run bin/fw.dart status`, which prints this for real.
/// Kept because it drives the plugin directly, with no Session in the way.
void main() {
  test('dump', () async {
    var root = findRepoRoot('..')!;
    var manifest = PluginManifest.parse(
      '{"version":1,'
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
    var session = Session.resolved(
      worktree: Worktree(path: root, branch: 'xha/overhaulrework'),
      workspace: workspace,
      manifest: manifest,
    );
    var plugins = buildNativeRegistry().resolve(session.cores);

    print('\n══ cold — nothing has been looked at ══\n');
    for (var report in session.reports) {
      print(report.toText());
    }

    // A CLI would subscribe for the duration of the request; this is that.
    for (var plugin in plugins.whereType<DependenciesPlugin>()) {
      for (var path in plugin.packages) {
        plugin.core.track(path);
      }
      for (var path in plugin.packages) {
        await plugin.core.serviceFor(path).dependencies.refresh();
      }
    }

    print('\n══ after subscribing ══\n');
    for (var report in session.reports) {
      print(report.toText());
    }

    workspace.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
