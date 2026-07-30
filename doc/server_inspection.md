# Server inspection — adapter snippets

`package:flutterware/server.dart` ships **primitives only**: `event`,
`span`/`spanSync`, `handle`, and zone correlation. Everything that binds them
to a specific framework or driver is a snippet on this page that you paste
into your server and own — deliberately, so the package stays dependency-free
and the redaction and capture policy is code you can read and edit (design
doc: `docs/superpowers/specs/2026-07-30-server-inspection-design.md`,
decisions 5 and 11).

A live, runnable version of the shelf + logging snippets is
[`examples/example/bin/example_server.dart`](../examples/example/bin/example_server.dart).

Everything below is inert in release builds (`dart compile` / `dart build`)
and on machines without `~/.flutterware/run`; there is no init call — the
first event publishes the server.

## HTTP in: shelf middleware

One `runZoned` is the whole correlation story: every query and log line
emitted below it is stamped with this request's id, which is what builds the
per-request waterfall and the N+1 badge.

```dart
import 'dart:async';
import 'package:flutterware/server.dart';
import 'package:shelf/shelf.dart';

Middleware inspect() {
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

// var handler = const Pipeline().addMiddleware(inspect()).addHandler(router);
```

## Logs: package:logging

The listener runs in whatever zone called `listen`, so correlation must come
from `record.zone` — the zone the log call happened in. Without that, log
lines lose their request id.

```dart
Logger.root.onRecord.listen((record) {
  (record.zone ?? Zone.current).run(() {
    FlutterwareServer.event('log', {
      'level': record.level.name,
      'logger': record.loggerName,
      'message': record.message,
      if (record.error != null) 'error': '${record.error}',
    });
  });
});
```

## Uncaught errors, outside any request

The middleware already reports a handler that throws. For everything else —
timers, queue consumers, fire-and-forget futures — wrap `main`'s body:

```dart
Future<void> main() async {
  await runZonedGuarded(() async {
    // ... start the server ...
  }, (error, stackTrace) {
    FlutterwareServer.event('log', {
      'level': 'SEVERE',
      'message': 'uncaught: $error',
      'error': '$stackTrace',
    });
  });
}
```

## SQL: drift

`QueryInterceptor` is the one hook that sees every statement. The `explain`
and `requery` handlers run **inside your server, on your own connection** —
that is why the GUI needs no driver and no credentials to show a real plan.

```dart
import 'package:drift/drift.dart';
import 'package:flutterware/server.dart';

class InspectingInterceptor extends QueryInterceptor {
  @override
  Future<T> _run<T>(String sql, List<Object?> args, Future<T> Function() body) {
    return FlutterwareServer.span('sql', {
      'query': sql,
      if (args.isNotEmpty) 'params': args,
    }, body);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _run(statement, args, () => executor.runSelect(statement, args));

  // Override runInsert / runUpdate / runDelete / runCustom the same way.
}

// db = MyDatabase(executor.interceptWith(InspectingInterceptor()));

void registerSqlCommands(MyDatabase db) {
  FlutterwareServer.handle('sql', 'explain', (params) async {
    var query = params['query']! as String;
    var rows = await db
        .customSelect('EXPLAIN QUERY PLAN $query')
        .get();
    return {'plan': [for (var row in rows) row.data]};
  });
  FlutterwareServer.handle('sql', 'requery', (params) async {
    var query = params['query']! as String;
    var rows = await db.customSelect(query).get();
    return {'rows': [for (var row in rows.take(50)) row.data]};
  });
}
```

## SQL: package:postgres

```dart
import 'package:flutterware/server.dart';
import 'package:postgres/postgres.dart';

Future<Result> query(
  Connection connection,
  String sql, {
  Map<String, Object?>? parameters,
}) {
  return FlutterwareServer.span('sql', {
    'query': sql,
    if (parameters != null) 'params': parameters.values.toList(),
  }, () => connection.execute(Sql.named(sql), parameters: parameters));
}

void registerSqlCommands(Connection connection) {
  FlutterwareServer.handle('sql', 'explain', (params) async {
    var rows = await connection.execute(
      'EXPLAIN ANALYZE ${params['query']}',
    );
    return {'plan': [for (var row in rows) row.first]};
  });
  FlutterwareServer.handle('sql', 'requery', (params) async {
    var rows = await connection.execute(params['query']! as String);
    return {'rows': [for (var row in rows.take(50)) row.toColumnMap()]};
  });
}
```

`EXPLAIN ANALYZE` **executes** the query. For statements with side effects,
or on data you care about, use plain `EXPLAIN` instead.

## SQL: package:sqlite3

```dart
import 'package:flutterware/server.dart';
import 'package:sqlite3/sqlite3.dart';

ResultSet query(Database db, String sql, [List<Object?> params = const []]) {
  return FlutterwareServer.spanSync('sql', {
    'query': sql,
    if (params.isNotEmpty) 'params': params,
  }, () => db.select(sql, params));
}

void registerSqlCommands(Database db) {
  FlutterwareServer.handle('sql', 'explain', (params) {
    var rows = db.select('EXPLAIN QUERY PLAN ${params['query']}');
    return {'plan': [for (var row in rows) row['detail']]};
  });
  FlutterwareServer.handle('sql', 'requery', (params) {
    var rows = db.select(params['query']! as String);
    return {'rows': rows.take(50).toList()};
  });
}
```

## HTTP out: the other half of a slow endpoint

Outgoing calls your handlers make, reported into the same waterfall:

```dart
import 'package:http/http.dart' as http;
import 'package:flutterware/server.dart';

class InspectingClient extends http.BaseClient {
  InspectingClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return FlutterwareServer.span('http-out', {
      'method': request.method,
      'url': '${request.url}',
    }, () => _inner.send(request));
  }
}
```

## Notes that apply to every snippet

- **Redaction is yours**: before reporting headers or parameters, drop what
  must not leave the process (`Authorization`, `Cookie`, password fields).
  The snippets above report no headers for exactly that reason — add them
  consciously.
- **`requery` re-executes the statement.** Registering it for a toy or a
  local dev database is convenient; think before registering it against
  anything shared.
- Every handler answer must be JSON-encodable; cap row counts (`take(50)`)
  — the wire is for inspection, not for bulk export.
