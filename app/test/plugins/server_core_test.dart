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

  test('a dropped connection reattaches without duplicating history', () async {
    inspector.addEvent('log', {'message': 'one'});
    await core.computeAll();
    core.track();
    await _until(() => core.servers.single.events.length == 1);

    // The drop: connection gone, server alive, handle still published.
    inspector.debugDropConnections();
    await _until(() => !core.servers.single.connected);
    expect(
      core.servers.single.stopped,
      isFalse,
      reason: 'a drop is not a death',
    );
    expect(
      core.servers.single.events,
      hasLength(1),
      reason: 'history survives',
    );

    // Reported while nobody is attached — only the ring has it.
    inspector.addEvent('log', {'message': 'two'});

    // The scheduled rescan reattaches; the full re-replay must dedupe.
    await _until(() => core.servers.single.events.length == 2);
    expect(core.servers.single.connected, isTrue);
    var ids = [for (var e in core.servers.single.events) e.id];
    expect(ids.toSet(), hasLength(2), reason: 'no duplicated replay');
  });

  test('a restart is a new session beside the greyed-out old one', () async {
    inspector.addEvent('log', {'message': 'from the first run'});
    await core.computeAll();
    core.track();
    await _until(() => core.servers.single.events.length == 1);

    await inspector.stop();
    var successor = ServerInspector.start(
      runDir: runDir.path,
      projectRoot: project.path,
      name: 'api',
      pid: pid + 1,
    );
    addTearDown(successor.stop);
    await successor.published;
    await core.computeAll();

    await _until(() {
      var servers = core.servers;
      return servers.length == 2 &&
          servers.any((s) => s.stopped) &&
          servers.any((s) => s.connected);
    });
    var old = core.servers.singleWhere((s) => s.stopped);
    expect(old.events.single.payload['message'], 'from the first run');
    expect(core.servers.singleWhere((s) => s.connected).events, isEmpty);
  });

  test('sqlStats groups by shape, heaviest total first', () {
    ServerEvent sql(String query, double ms) => ServerEvent(
      channel: 'sql',
      id: 0,
      time: DateTime.now(),
      payload: {'query': query, 'ms': ms},
      isReplay: false,
    );
    var stats = sqlStats([
      sql('select count(*) from posts where user_id = 1', 2),
      sql('select count(*) from posts where user_id = 2', 3),
      sql('select * from users', 20),
      ServerEvent(
        channel: 'log',
        id: 0,
        time: DateTime.now(),
        payload: {'message': 'not sql'},
        isReplay: false,
      ),
    ]);

    expect(stats, hasLength(2));
    expect(stats.first.normalized, 'select * from users');
    expect(stats.first.totalMs, 20);
    var grouped = stats.last;
    expect(grouped.count, 2);
    expect(grouped.totalMs, 5);
    expect(grouped.maxMs, 3);
    expect(
      grouped.latest.payload['query'],
      'select count(*) from posts where user_id = 2',
      reason: 'explain acts on a real query, not the ?-shape',
    );
  });

  test('explain runs inside the server and answers over the wire', () async {
    inspector.registerHandler('sql', 'explain', (params) {
      return {'plan': 'SCAN (${params['query']})'};
    });
    inspector.addEvent('sql', {'query': 'select 1', 'ms': 1.0});
    await core.computeAll();
    core.track();
    await _until(() => core.servers.single.connected);

    var response = await sqlCommand(core.servers.single, 'explain', 'select 1');
    expect(response['plan'], 'SCAN (select 1)');

    // No requery handler registered — the panel shows this as text.
    await expectLater(
      () => sqlCommand(core.servers.single, 'requery', 'select 1'),
      throwsA(isA<ServerRequestException>()),
    );
  });

  test('details are fetched lazily through the tracked server', () async {
    inspector.addEvent(
      'http',
      {'path': '/x', 'status': 200},
      details: {'responseBody': 'hello'},
    );
    await core.computeAll();
    core.track();
    await _until(() => core.servers.single.connected);

    var event = core.servers.single.events.single;
    var details = await core.servers.single.detailsFor(event);
    expect(details!['responseBody'], 'hello');
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
