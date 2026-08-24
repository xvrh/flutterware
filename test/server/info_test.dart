import 'dart:convert';
import 'dart:io';

import 'package:flutterware/server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A run dir short enough that `srv-*.sock` stays under the 104-byte
/// `sun_path` cap — `Directory.systemTemp` on macOS is deep enough to blow it.
Future<Directory> shortTempDir() {
  var base = Directory.systemTemp;
  if (p.join(base.path, 'x' * 45).length > 90) base = Directory('/tmp');
  return base.createTemp('fw_srv_');
}

ServerEvent _event(
  String channel,
  Map<String, Object?> payload, {
  int id = 1,
}) => ServerEvent(
  channel: channel,
  id: id,
  time: DateTime.now(),
  payload: payload,
  isReplay: false,
);

void main() {
  group('ServerInfo json', () {
    test('round-trips, emitting only the sections present', () {
      var info = ServerInfo(
        baseUrl: 'http://localhost:8080',
        links: [ServerLink('Health', '/health', description: 'liveness')],
      );
      var json = info.toJson();
      expect(json.keys, ['baseUrl', 'links']);

      var back = ServerInfo.fromJson(json);
      expect(back.baseUrl, 'http://localhost:8080');
      expect(back.environment, isNull);
      expect(back.links!.single.label, 'Health');
      expect(back.links!.single.description, 'liveness');
      expect(back.connections, isNull);
    });

    test('tolerates garbage the way tryDecodeFrame does', () {
      var info = ServerInfo.fromJson({
        'baseUrl': 42,
        'links': [
          {'label': 'ok', 'url': '/fine'},
          {'label': 'no url'},
          'not even a map',
        ],
        'connections': 'nope',
        'config': {
          'Group': {'k': 'v'},
          'flat value': 12,
        },
      });
      expect(info.baseUrl, isNull);
      expect([for (var l in info.links!) l.label], ['ok']);
      expect(info.connections, isNull);
      expect(info.config, {
        'Group': {'k': 'v'},
      });
    });
  });

  group('ServerInfo.fromEvents', () {
    test('keeps the latest value per section', () {
      var info = ServerInfo.fromEvents([
        _event(infoChannel, {
          'environment': 'dev',
          'links': [
            {'label': 'Old', 'url': '/old'},
          ],
        }),
        _event('http', {'path': '/noise'}, id: 2),
        _event(infoChannel, {
          'links': [
            {'label': 'New', 'url': '/new'},
          ],
        }, id: 3),
      ]);
      expect(info.environment, 'dev', reason: 'untouched section survives');
      expect(info.links!.single.label, 'New', reason: 'named section replaced');
    });

    test('no info events reads as empty, not as an error', () {
      var info = ServerInfo.fromEvents([
        _event('http', {'path': '/x'}),
      ]);
      expect(info.isEmpty, isTrue);
    });
  });

  group('resolveLinkUrl', () {
    test('absolute stays, relative resolves against the base', () {
      expect(
        resolveLinkUrl('https://grafana.example/d/1', baseUrl: 'http://x'),
        'https://grafana.example/d/1',
      );
      expect(
        resolveLinkUrl('/health', baseUrl: 'http://localhost:8080'),
        'http://localhost:8080/health',
      );
    });

    test(
      'relative with nothing to resolve against is null, not a dead link',
      () {
        expect(resolveLinkUrl('/health'), isNull);
        expect(resolveLinkUrl('/health', baseUrl: 'not a url'), isNull);
      },
    );
  });

  group('masking', () {
    test('masks the password of a url-shaped dsn', () {
      expect(
        maskDsn('postgres://app:s3cret@localhost:5432/app'),
        'postgres://app:••••@localhost:5432/app',
      );
    });

    test('masks password= segments of an ado-style dsn', () {
      expect(
        maskDsn('Server=db;User=app;Password=s3cret;Timeout=5'),
        'Server=db;User=app;Password=••••;Timeout=5',
      );
    });

    test('leaves secretless strings alone', () {
      expect(maskDsn('sqlite:///tmp/app.db'), 'sqlite:///tmp/app.db');
      expect(maskDsn('redis://localhost:6379/0'), 'redis://localhost:6379/0');
    });

    test('secret-like keys are eager, but not "monkey"-eager', () {
      expect(isSecretLikeKey('databasePassword'), isTrue);
      expect(isSecretLikeKey('API_KEY'), isTrue);
      expect(isSecretLikeKey('sessionToken'), isTrue);
      expect(isSecretLikeKey('key'), isTrue);
      expect(isSecretLikeKey('monkey'), isFalse);
      expect(isSecretLikeKey('timeout'), isFalse);
    });
  });

  group('handle mirror', () {
    test(
      'info published before the handle lands in the initial write',
      () async {
        var runDir = await shortTempDir();
        addTearDown(() => runDir.delete(recursive: true));
        var inspector = ServerInspector.start(
          runDir: runDir.path,
          projectRoot: '/repo/app',
          name: 'api',
        );
        addTearDown(inspector.stop);
        // Before `published` — the first event of a server's life is often the
        // info call that activated it.
        inspector.addEvent(infoChannel, {
          'baseUrl': 'http://localhost:8080',
          'environment': 'dev',
        });
        await inspector.published;

        var handle = scanServerHandles(runDir.path).single;
        expect(handle.baseUrl, 'http://localhost:8080');
        expect(handle.environment, 'dev');
      },
    );

    test(
      'a later publish rewrites the handle; untouched fields survive',
      () async {
        var runDir = await shortTempDir();
        addTearDown(() => runDir.delete(recursive: true));
        var inspector = ServerInspector.start(
          runDir: runDir.path,
          projectRoot: '/repo/app',
          name: 'api',
        );
        addTearDown(inspector.stop);
        await inspector.published;
        expect(scanServerHandles(runDir.path).single.baseUrl, isNull);

        inspector.addEvent(infoChannel, {
          'baseUrl': 'http://localhost:8080',
          'environment': 'dev',
        });
        inspector.addEvent(infoChannel, {'baseUrl': 'http://localhost:9090'});

        var handle = scanServerHandles(runDir.path).single;
        expect(handle.baseUrl, 'http://localhost:9090');
        expect(handle.environment, 'dev');
      },
    );

    test('a handle from before the mirror still reads', () async {
      var runDir = await shortTempDir();
      addTearDown(() => runDir.delete(recursive: true));
      var old = ServerHandle(
        projectRoot: '/repo/app',
        name: 'api',
        socketPath: p.join(runDir.path, 'x.sock'),
        pid: 1,
        startedAt: DateTime.now(),
      );
      File(p.join(runDir.path, 'srv-00000000-api-1.json'))
          .writeAsStringSync(jsonEncode(old.toJson()));

      var read = scanServerHandles(runDir.path).single;
      expect(read.baseUrl, isNull);
      expect(read.environment, isNull);
    });
  });

  group('over the wire', () {
    test('info publishes through the sugar, replays, and merges', () async {
      var runDir = await shortTempDir();
      addTearDown(() => runDir.delete(recursive: true));
      var inspector = ServerInspector.start(
        runDir: runDir.path,
        projectRoot: '/repo/app',
        name: 'api',
      );
      addTearDown(FlutterwareServer.reset);
      FlutterwareServer.debugAttachInspector(inspector);
      await inspector.published;

      FlutterwareServer.info(
        ServerInfo(
          baseUrl: 'http://localhost:8080',
          connections: [
            ServerConnection(
              'postgres',
              'postgres://app:s3cret@localhost/app',
              label: 'main',
            ),
          ],
        ),
      );
      // A later publish updates one section and leaves the rest.
      FlutterwareServer.info(ServerInfo(environment: 'dev'));

      var client = await ServerAttachClient.connect(
        scanServerHandles(runDir.path).single,
      );
      addTearDown(client.close);
      while (!client.replayComplete) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      var info = ServerInfo.fromEvents(client.received);
      expect(info.baseUrl, 'http://localhost:8080');
      expect(info.environment, 'dev');
      expect(info.connections!.single.kind, 'postgres');
      expect(info.connections!.single.label, 'main');
    });
  });
}
