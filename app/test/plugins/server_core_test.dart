import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware/server.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/server_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';

/// The core against a real inspected server — a [ServerInspector] pointed at
/// a temp run dir, attached to over a real unix socket. What is asserted is
/// what `fw` and an agent see through [PluginReport] and `invoke`; the panel
/// draws the same core.
void main() {
  late Directory runDir;
  late Directory project;
  late ServerInspector inspector;
  late ServerCore core;

  setUp(() async {
    runDir = Directory.systemTemp.createTempSync('fw-srv-run-');
    project = Directory.systemTemp.createTempSync('fw-srv-project-');
    ServerCore.runDirProvider = () => runDir.path;
    inspector = ServerInspector.start(
      runDir: runDir.path,
      projectRoot: project.path,
      name: 'api',
    );
    await inspector.published;

    var worktree = Worktree(path: project.path);
    core = ServerCore(
      PluginHost(
        id: serverPluginId,
        label: 'Server',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [],
          discovered: [],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
      ),
    );
  });

  tearDown(() async {
    core.dispose();
    await inspector.stop();
    ServerCore.runDirProvider = flutterwareRunDir;
    for (var dir in [runDir, project]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  test('computeAll discovers the announced server without attaching', () async {
    await core.computeAll();
    var report = core.report;
    expect(report.status.message, '1 running');
    expect(report.children.single.id, 'api');
    expect(core.servers.single.client, isNull);
  });

  test('a server outside the worktree is not listed', () async {
    var elsewhere = ServerInspector.start(
      runDir: runDir.path,
      projectRoot: Directory.systemTemp.path,
      name: 'other',
    );
    addTearDown(elsewhere.stop);
    await elsewhere.published;

    await core.computeAll();
    expect(core.servers.map((s) => s.handle.name), ['api']);
  });

  test('the requests action returns the correlated waterfall', () async {
    inspector.addEvent('http', {
      'method': 'GET',
      'path': '/users',
      'status': 200,
      'ms': 10.0,
    }, rid: 'req-1');
    inspector.addEvent('sql', {'query': 'select 1', 'ms': 2.0}, rid: 'req-1');

    await core.computeAll();
    var result = (await core.invoke('requests'))! as Map<String, Object?>;
    var servers = result['servers']! as List;
    var requests = (servers.single as Map)['requests']! as List;
    var request = (requests.single as Map).cast<String, Object?>();
    expect(request['path'], '/users');
    var caused = (request['caused']! as List).cast<Map>();
    expect(caused.single['query'], 'select 1');
  });

  test('track attaches, replays, and follows live events', () async {
    inspector.addEvent('log', {'message': 'before'});
    await core.computeAll();
    core.track();

    await _until(() => core.servers.single.events.isNotEmpty);
    expect(core.servers.single.events.single.payload['message'], 'before');

    inspector.addEvent('log', {'message': 'after'});
    await _until(() => core.servers.single.events.length == 2);
    expect(core.report.view.toText(), contains('2 events'));
  });
}

Future<void> _until(bool Function() condition) async {
  var deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached in 5s');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
