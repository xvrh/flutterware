import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/ui_catalog_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// Who owns a served page, and for how long.
///
/// The plugin does, not the dialog that asked: the dialog is closed the moment
/// the tab is open, and a server that went with it would leave that tab showing
/// a connection error. The worktree is the lifetime, which is what [dispose]
/// here stands for.
void main() {
  late Directory root;
  late UiCatalogPlugin plugin;
  var disposed = false;

  /// `ChangeNotifier.dispose` is documented as single-use and asserts on a
  /// second call, so the test that disposes early says so rather than leaving
  /// tearDown to trip over it.
  void dispose() {
    if (disposed) return;
    disposed = true;
    plugin.dispose();
  }

  setUp(() {
    disposed = false;
    root = Directory.systemTemp.createTempSync('fw_catalog_serve_test');
    Directory(p.join(root.path, 'build', 'catalog', 'web'))
      ..createSync(recursive: true)
      ..childFile('index.html').writeAsStringSync('<!doctype html>');

    var worktree = Worktree(path: root.path);
    plugin = UiCatalogPlugin(
      UiCatalogCore(
        PluginHost(
          id: uiCatalogPluginId,
          label: 'UI catalog',
          worktree: worktree,
          workspace: Workspace(
            root: worktree.path,
            declared: [Pkg('.')],
            discovered: const ['.'],
            appContext: AppContext(logger: LogClient.print()),
            flutterSdk: FlutterSdkPath('/tmp/flutter'),
          ),
          config: const {
            'packages': [
              {'path': '.'},
            ],
          },
        ),
      ),
    );
  });

  tearDown(() {
    dispose();
    root.deleteSync(recursive: true);
  });

  Future<bool> reachable(Uri url) async {
    var client = HttpClient();
    try {
      var response = await (await client.getUrl(url)).close();
      await response.drain<void>();
      return response.statusCode == 200;
    } on SocketException {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  test('a relative output is resolved against the worktree', () async {
    var url = await plugin.serveBuild('build/catalog/web');

    expect(url.host, '127.0.0.1');
    expect(await reachable(url), isTrue);
  });

  test('serving the same page twice keeps the port', () async {
    var first = await plugin.serveBuild('build/catalog/web');
    var second = await plugin.serveBuild('build/catalog/web');

    // A rebuild writes over the same directory, and the tab that is already
    // open is the one that should show it. A new port each time would leave
    // that tab pointed at a server nobody is going to look at again.
    expect(second, first);
    expect(await reachable(first), isTrue);
  });

  test('a changed base href rebinds rather than answering 404', () async {
    var atRoot = await plugin.serveBuild('build/catalog/web');
    var atPrefix = await plugin.serveBuild(
      'build/catalog/web',
      basePath: '/catalog/',
    );

    expect(atPrefix.path, '/catalog/');
    expect(await reachable(atPrefix), isTrue);
    // The old mount is gone with the server that held it — the same files under
    // a different base href are a different page to a browser, and keeping both
    // would serve one of them broken.
    expect(await reachable(atRoot), isFalse);
  });

  test('closing the worktree stops the server', () async {
    var url = await plugin.serveBuild('build/catalog/web');
    expect(await reachable(url), isTrue);

    dispose();
    expect(await reachable(url), isFalse);
  });
}

extension on Directory {
  File childFile(String name) => File(p.join(path, name));
}
