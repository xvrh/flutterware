/// A toy HTTP server, instrumented for flutterware's server inspection.
///
/// Run it any way you like — `dart run bin/example_server.dart`, the IDE's run
/// button, an agent — then `curl localhost:8080/users`. No flutterware launch
/// step: the library announces itself in `~/.flutterware/run` on first use,
/// and the GUI / `fw` / MCP attach to that.
///
/// The `_inspect` middleware and `_query` wrapper below are the copy-paste
/// adapters the design doc describes (spec decision 5): a project pastes and
/// adapts them, only the primitives live in `package:flutterware/server.dart`.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutterware/server.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

final _log = Logger('example_server');

Future<void> main() async {
  // Adapter: forward `package:logging` to the `log` channel. The listener
  // runs in whatever zone called `listen`, so correlation must come from
  // `record.zone` — the zone the log call happened in.
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    stdout.writeln(record);
    (record.zone ?? Zone.current).run(() {
      FlutterwareServer.event('log', {
        'level': record.level.name,
        'logger': record.loggerName,
        'message': record.message,
        if (record.error != null) 'error': '${record.error}',
      });
    });
  });

  // Command handlers run *inside* this process, against its own "database" —
  // which is why the GUI can explain and re-run queries with no DB config.
  FlutterwareServer.handle('sql', 'explain', (params) {
    return {'plan': 'SCAN ${params['query']} (toy database, toy plan)'};
  });
  FlutterwareServer.handle('sql', 'requery', (params) {
    return {'rows': _database.execute(params['query']?.toString() ?? '')};
  });

  var handler = const Pipeline().addMiddleware(_inspect()).addHandler(_route);
  var server = await shelf_io.serve(
    handler,
    InternetAddress.loopbackIPv4,
    8080,
  );
  _log.info('listening on http://localhost:${server.port}');
}

/// Adapter: the shelf middleware. One `runZoned` is the whole correlation
/// story — every query and log line emitted below it carries this request's id.
Middleware _inspect() {
  var nextRequestId = 1;
  return (inner) => (request) {
    var id = 'req-${nextRequestId++}';
    return runZoned(() async {
      var watch = Stopwatch()..start();
      try {
        var response = await inner(request);
        FlutterwareServer.event('http', {
          'method': request.method,
          'path': '/${request.url.path}',
          'status': response.statusCode,
          'ms': watch.elapsedMicroseconds / 1000,
        });
        return response;
      } catch (e) {
        FlutterwareServer.event('http', {
          'method': request.method,
          'path': '/${request.url.path}',
          'status': 500,
          'ms': watch.elapsedMicroseconds / 1000,
          'error': '$e',
        });
        rethrow;
      }
    }, zoneValues: {FlutterwareServer.requestIdKey: id});
  };
}

/// Adapter: a query wrapper — what a drift `QueryInterceptor` or a thin
/// sqlite3/postgres wrapper reduces to.
List<Map<String, Object?>> _query(String sql) {
  return FlutterwareServer.spanSync('sql', {'query': sql}, () {
    return _database.execute(sql);
  });
}

Future<Response> _route(Request request) async {
  switch ('/${request.url.path}') {
    case '/':
      return Response.ok('example server\n');
    case '/users':
      var users = _query('select id, name from users');
      // Deliberately N+1: one query per user, inside one request — the shape
      // the GUI's correlation view exists to make visible.
      for (var user in users) {
        _query('select count(*) from posts where user_id = ${user['id']}');
      }
      _log.info('listed ${users.length} users');
      return Response.ok('${users.map((u) => u['name']).join('\n')}\n');
    case '/slow':
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _query('select * from posts order by created_at desc limit 50');
      return Response.ok('done being slow\n');
    case '/error':
      _log.severe('about to fail on purpose');
      throw StateError('deliberate failure for the errors view');
    default:
      return Response.notFound('nothing at ${request.url.path}\n');
  }
}

/// A "database" with predictable latency, so timings in the GUI mean something.
final _database = _ToyDatabase();

class _ToyDatabase {
  final _users = [
    {'id': 1, 'name': 'ada'},
    {'id': 2, 'name': 'grace'},
    {'id': 3, 'name': 'edsger'},
  ];

  List<Map<String, Object?>> execute(String sql) {
    var until = DateTime.now().add(const Duration(milliseconds: 2));
    while (DateTime.now().isBefore(until)) {
      // Busy-wait: a sync "query" that visibly costs something.
    }
    if (sql.contains('from users')) return _users;
    return [
      {'count': sql.length},
    ];
  }
}
