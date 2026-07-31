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

  test(
    'the errors action collects failures with their causing request',
    () async {
      inspector.addEvent('http', {
        'method': 'GET',
        'path': '/ok',
        'status': 200,
      }, rid: 'r1');
      inspector.addEvent('log', {
        'level': 'SEVERE',
        'message': 'about to fail',
      }, rid: 'r2');
      inspector.addEvent('http', {
        'method': 'GET',
        'path': '/bad',
        'status': 500,
        'error': 'Bad state',
      }, rid: 'r2');

      await core.computeAll();
      var result = (await core.invoke('errors'))! as Map<String, Object?>;
      var servers = result['servers']! as List;
      var errors = ((servers.single as Map)['errors']! as List).cast<Map>();

      expect(errors, hasLength(2), reason: 'the 200 is not an error');
      expect(errors.first['path'], '/bad', reason: 'newest first');
      var log = errors.last;
      expect(log['message'], 'about to fail');
      expect(
        (log['request']! as Map)['path'],
        '/bad',
        reason: 'a severe log carries the request it happened under',
      );
    },
  );

  test('the sql action returns the aggregate, heaviest first', () async {
    inspector.addEvent('sql', {'query': 'select 1', 'ms': 1.0});
    inspector.addEvent('sql', {
      'query': 'select count(*) from t where id = 1',
      'ms': 5.0,
    });
    inspector.addEvent('sql', {
      'query': 'select count(*) from t where id = 2',
      'ms': 5.0,
    });

    await core.computeAll();
    var result = (await core.invoke('sql'))! as Map<String, Object?>;
    var servers = result['servers']! as List;
    var queries = ((servers.single as Map)['queries']! as List).cast<Map>();

    expect(queries.first['query'], 'select count(*) from t where id = ?');
    expect(queries.first['count'], 2);
    expect(queries.first['totalMs'], 10.0);
    expect(queries.last['query'], 'select ?');
  });

  test('the info action masks secrets and resolves links', () async {
    inspector.addEvent(infoChannel, {
      'baseUrl': 'http://localhost:8080',
      'links': [
        {'label': 'Health', 'url': '/health'},
      ],
      'connections': [
        {'kind': 'postgres', 'dsn': 'postgres://app:s3cret@localhost/app'},
      ],
      'config': {
        'Auth': {'apiKey': 'real-key', 'timeoutMs': 250},
      },
    });
    // A later publish updates one section, leaving the rest.
    inspector.addEvent(infoChannel, {'environment': 'dev'});

    await core.computeAll();
    var result = (await core.invoke('info'))! as Map<String, Object?>;
    var servers = result['servers']! as List;
    var info = ((servers.single as Map)['info']! as Map)
        .cast<String, Object?>();

    expect(info['baseUrl'], 'http://localhost:8080');
    expect(info['environment'], 'dev', reason: 'sections merge across events');
    var link = ((info['links']! as List).single as Map).cast<String, Object?>();
    expect(
      link['url'],
      'http://localhost:8080/health',
      reason: 'relative links leave here absolute',
    );
    var connection = ((info['connections']! as List).single as Map)
        .cast<String, Object?>();
    expect(connection['dsn'], 'postgres://app:••••@localhost/app');
    var auth = (((info['config']! as Map)['Auth']!) as Map)
        .cast<String, Object?>();
    expect(auth['apiKey'], '••••');
    expect(auth['timeoutMs'], 250, reason: 'only secret-like keys mask');
  });

  test('the info action says so when nothing was published', () async {
    inspector.addEvent('log', {'message': 'no info here'});
    await core.computeAll();
    var result = (await core.invoke('info'))! as Map<String, Object?>;
    var servers = result['servers']! as List;
    var info = ((servers.single as Map)['info']! as Map)
        .cast<String, Object?>();
    expect(info['note'], contains('FlutterwareServer.info'));
  });

  test('the report shows the mirrored base URL without attaching', () async {
    inspector.addEvent(infoChannel, {
      'baseUrl': 'http://localhost:8080',
      'environment': 'dev',
    });
    await core.computeAll();
    expect(
      core.report.children.single.status.message,
      'pid $pid · http://localhost:8080 · dev',
    );
    expect(core.servers.single.client, isNull, reason: 'scan only, no socket');
  });

  test('a tracked server exposes the reduced info to the panel', () async {
    inspector.addEvent(infoChannel, {'environment': 'staging'});
    await core.computeAll();
    core.track();
    await _until(() => core.servers.single.events.isNotEmpty);
    expect(core.servers.single.info.environment, 'staging');
  });

  group('curlCommand', () {
    ServerEvent request(Map<String, Object?> payload) => ServerEvent(
      channel: 'http',
      id: 1,
      time: DateTime.now(),
      payload: payload,
      isReplay: false,
    );
    var info = ServerInfo(baseUrl: 'http://localhost:8080');

    test('a bare GET is one line', () {
      expect(
        curlCommand(info, request({'method': 'GET', 'path': '/users'})),
        "curl 'http://localhost:8080/users'",
      );
    });

    test('headers and body continue over lines; curl-derived headers drop', () {
      var command = curlCommand(
        info,
        request({'method': 'POST', 'path': '/echo'}),
        details: {
          'requestHeaders': {
            'content-type': 'text/plain',
            'host': 'localhost:8080',
            'content-length': '11',
            'authorization': '<redacted>',
          },
          'requestBody': "it's hello",
        },
      );
      expect(
        command,
        "curl -X POST 'http://localhost:8080/echo' \\\n"
        "  -H 'content-type: text/plain' \\\n"
        "  -H 'authorization: <redacted>' \\\n"
        r"  --data-raw 'it'\''s hello'",
      );
    });

    test('no published baseUrl is null, not a relative non-command', () {
      expect(curlCommand(ServerInfo(), request({'path': '/users'})), isNull);
    });
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
