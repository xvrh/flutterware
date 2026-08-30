import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/previews/catalog_roots.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:test/test.dart';

/// The project this repo actually has: previews scans `tool/catalog`, motion
/// scans the narrower `tool/catalog/demos`. Before this resolution existed the
/// two hashed to different daemon addresses and compiled the same files twice.
PluginManifest get _manifest => const PluginManifest([
  PluginDeclaration(
    id: previewsPluginId,
    label: 'Previews',
    config: {
      'packages': [
        {'path': 'app', 'directory': 'tool/catalog'},
        {'path': 'examples/example'},
      ],
    },
  ),
  PluginDeclaration(
    id: 'flutterware.motion',
    label: 'Motion',
    config: {
      'packages': [
        {'path': 'app', 'directory': 'tool/catalog/demos'},
      ],
    },
  ),
]);

PluginHost _hostFor(String id) => PluginHost(
  id: id,
  label: id,
  worktree: Worktree(path: '/tmp/w'),
  workspace: Workspace(
    root: '/tmp/w',
    declared: [Pkg('app')],
    discovered: const ['app'],
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/tmp/sdk'),
  ),
  config: _manifest.plugins.firstWhere((p) => p.id == id).config,
  catalogRoots: catalogRootsFrom(_manifest),
);

void main() {
  test('a package with no declared directory gets the whole package', () {
    expect(catalogRootsFrom(_manifest)['examples/example'], [
      defaultCatalogRoot,
    ]);
  });

  test('the declared directory is what the catalog looks in', () {
    expect(catalogRootsFrom(_manifest)['app'], ['tool/catalog']);
  });

  test('every plugin is told the same place, whatever it declared', () {
    // The invariant. Motion declares a *narrower* directory and still renders
    // through the catalog's roots — because a narrower root would not narrow
    // the catalog, it would fork the compiler and give the panel a second warm
    // kernel that nothing keeps current.
    expect(
      _hostFor('flutterware.motion').catalogRootsFor('app'),
      _hostFor(previewsPluginId).catalogRootsFor('app'),
    );
    expect(_hostFor('flutterware.motion').catalogRootsFor('app'), [
      'tool/catalog',
    ]);
  });

  test('a package nobody declared falls back rather than throwing', () {
    expect(_hostFor('flutterware.motion').catalogRootsFor('nope'), [
      defaultCatalogRoot,
    ]);
  });
}
