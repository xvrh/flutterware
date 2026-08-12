import 'dart:async';

import 'package:flutterware/channels.dart';
import 'package:flutterware/src/devbar/plugins/database.dart';
import 'package:test/test.dart';

/// A scripted database: no sqlite anywhere, per the design's build step 2.
class _FakeDb {
  /// Answers every query. Tests swap it to script results or to throw.
  Future<List<Map<String, Object?>>> Function(String sql, List<Object?> args)
  onQuery = (_, _) async => const [];

  final executed = <(String, List<Object?>)>[];
  final queried = <(String, List<Object?>)>[];

  /// Sync, so a test's `updates.add` lands before the next line runs.
  final updates = StreamController<Set<String>>.broadcast(sync: true);

  Future<void> close() => updates.close();

  DatabaseAdapter adapter({
    bool withUpdates = true,
    bool writable = false,
    DatabaseWatch? watch,
  }) => DatabaseAdapter(
    query: (sql, args) {
      queried.add((sql, args));
      return onQuery(sql, args);
    },
    updates: withUpdates ? updates.stream : null,
    watch: watch,
    execute: writable
        ? (sql, args) async {
            executed.add((sql, args));
            return const [];
          }
        : null,
  );
}

void main() {
  late InspectorCore core;
  late Panels panels;
  late _FakeDb db;

  setUp(() {
    core = InspectorCore(identity: () => const {});
    panels = Panels(core);
    db = _FakeDb();
    addTearDown(() => db.close());
  });

  /// Mounts [adapter] the way the bridge does, with a zero coalescing window
  /// so a test turn of the event loop is a full window.
  (Panel, DatabasePanelSource) mount(DatabaseAdapter adapter) {
    var source = DatabasePanelSource(adapter, coalesceWindow: Duration.zero);
    addTearDown(source.dispose);
    var panel = panels.add(source.panelId, source.panelLabel);
    source.describePanel(panel);
    return (panel, source);
  }

  /// The feed events a fresh attacher would replay, payloads only.
  List<Map<String, Object?>> ringed(String channel) {
    var peer = _Peer();
    core.attach(peer, 1);
    return [
      for (var frame in peer.frames)
        if (frame['t'] == 'event' && frame['ch'] == channel)
          (frame['p']! as Map).cast<String, Object?>(),
    ];
  }

  Map<String, Object?> details(int eventId) {
    var peer = _Peer();
    core.handleFrame(peer, {
      'ch': 'meta',
      't': 'req',
      'id': 1,
      'm': 'detail',
      'p': {'event': eventId},
    });
    var payload = (peer.frames.single['p']! as Map).cast<String, Object?>();
    return (payload['details']! as Map).cast<String, Object?>();
  }

  group('descriptor', () {
    test('declares only what the adapter can answer', () {
      var (panel, _) = mount(db.adapter(withUpdates: false));
      var descriptor = panel.descriptor;
      expect(descriptor.id, 'db:main');
      expect(descriptor.states.single.id, 'schema');
      expect(descriptor.actions.map((a) => a.id), ['query']);
      expect(descriptor.feeds, isEmpty, reason: 'no updates, no feeds');
    });

    test('updates unlock the changes feed and the watch surface', () {
      var (panel, _) = mount(db.adapter());
      var descriptor = panel.descriptor;
      expect(descriptor.feeds.map((f) => f.id), ['changes', 'watch']);
      expect(descriptor.actions.map((a) => a.id), [
        'query',
        'watch',
        'unwatch',
      ]);
      expect(descriptor.feeds.last.itemActions.single.id, 'explain');
    });

    test('execute exists only when the app provided the function', () async {
      var (bare, _) = mount(db.adapter());
      expect(
        bare.descriptor.actions.map((a) => a.id),
        isNot(contains('execute')),
      );
      await expectLater(
        () => bare.run('execute', {'sql': 'x'}),
        throwsArgumentError,
      );

      db = _FakeDb();
      var writable = DatabasePanelSource(db.adapter(writable: true));
      addTearDown(writable.dispose);
      var panel = panels.add(writable.panelId, writable.panelLabel);
      writable.describePanel(panel);
      var execute = panel.descriptor.actions.singleWhere(
        (a) => a.id == 'execute',
      );
      expect(execute.danger, isTrue);
      await panel.run('execute', {'sql': 'DELETE FROM todos'});
      expect(db.executed.single.$1, 'DELETE FROM todos');
    });

    test('a second database is a second panel', () {
      var one = DatabasePanelSource(db.adapter());
      var two = DatabasePanelSource(
        DatabaseAdapter(name: 'cache', query: (_, _) async => const []),
      );
      expect(one.panelId, 'db:main');
      expect(one.panelLabel, 'Database');
      expect(two.panelId, 'db:cache');
      expect(two.panelLabel, 'Database (cache)');
    });
  });

  group('query', () {
    test('answers rows with the fixed reply shape', () async {
      db.onQuery = (_, _) async => [
        {'id': 1, 'title': 'first'},
        {'id': 2, 'title': 'second'},
      ];
      var (panel, _) = mount(db.adapter());
      var reply =
          (await panel.run('query', {'sql': 'SELECT * FROM todos'}))! as Map;
      expect(reply['columns'], ['id', 'title']);
      expect(reply['rowCount'], 2);
      expect((reply['rows']! as List).length, 2);
      expect(reply.containsKey('truncated'), isFalse);
    });

    test('truncates loudly at the limit', () async {
      db.onQuery = (_, _) async => [
        for (var i = 0; i < 10; i++) {'id': i},
      ];
      var (panel, _) = mount(db.adapter());
      var reply =
          (await panel.run('query', {'sql': 'SELECT 1', 'limit': 3}))! as Map;
      expect((reply['rows']! as List).length, 3);
      expect(reply['rowCount'], 10);
      expect(reply['truncated'], isTrue);
    });

    test('binds args given as a list or as a JSON string', () async {
      var (panel, _) = mount(db.adapter());
      await panel.run('query', {
        'sql': 'SELECT ?',
        'args': [42],
      });
      await panel.run('query', {'sql': 'SELECT ?', 'args': '[43]'});
      expect(db.queried.map((q) => q.$2), [
        [42],
        [43],
      ]);
    });

    test('blobs and exotic values survive as markers', () async {
      db.onQuery = (_, _) async => [
        {
          'blob': [1, 2, 3],
          'when': DateTime.utc(2026),
          'n': 1.5,
          'null': null,
        },
      ];
      var (panel, _) = mount(db.adapter());
      var reply = (await panel.run('query', {'sql': 'x'}))! as Map;
      var row = (reply['rows']! as List).single as Map;
      expect(row['blob'], '<blob 3 bytes>');
      expect(row['when'], '2026-01-01 00:00:00.000Z');
      expect(row['n'], 1.5);
      expect(row['null'], isNull);
    });

    test('refuses missing sql and a bad limit with a sentence', () async {
      var (panel, _) = mount(db.adapter());
      await expectLater(() => panel.run('query'), throwsArgumentError);
      await expectLater(
        () => panel.run('query', {'sql': 'x', 'limit': 'lots'}),
        throwsArgumentError,
      );
    });
  });

  test('schema reads sqlite_master, columns and counts', () async {
    db.onQuery = (sql, _) async {
      if (sql.contains('sqlite_master')) {
        return [
          {'name': 'todos'},
        ];
      }
      if (sql.startsWith('PRAGMA')) {
        return [
          {'name': 'id', 'type': 'INTEGER'},
          {'name': 'title', 'type': 'TEXT'},
        ];
      }
      return [
        {'c': 12},
      ];
    };
    var (panel, _) = mount(db.adapter());
    var schema = await panel.readState('schema');
    expect(schema, {
      'tables': [
        {'name': 'todos', 'rows': 12, 'columns': 'id INTEGER, title TEXT'},
      ],
    });
  });

  group('changes', () {
    test('first tick speaks immediately, a burst coalesces', () async {
      var (_, _) = mount(db.adapter());
      db.updates.add({'todos'});
      db.updates.add({'todos', 'tags'});
      db.updates.add({'tags'});
      await Future<void>.delayed(Duration.zero);

      var events = ringed('db:main/changes');
      expect(events.first, {'tables': 'todos', 'transactions': 1});
      expect(events.last, {'tables': 'tags todos', 'transactions': 2});
      expect(events, hasLength(2), reason: 'three transactions, two events');
    });

    test('nothing is emitted after dispose', () async {
      var (_, source) = mount(db.adapter());
      source.dispose();
      db.updates.add({'todos'});
      await Future<void>.delayed(Duration.zero);
      expect(ringed('db:main/changes'), isEmpty);
    });
  });

  group('watch', () {
    test('fallback: initial snapshot, then one per coalesced tick', () async {
      var rows = [
        {'id': 1},
      ];
      db.onQuery = (_, _) async => rows;
      var (panel, _) = mount(db.adapter());

      var reply =
          (await panel.run('watch', {'sql': 'SELECT * FROM todos'}))! as Map;
      expect(reply['watch'], 1);
      await Future<void>.delayed(Duration.zero);

      rows = [
        {'id': 1},
        {'id': 2},
      ];
      db.updates.add({'todos'});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      var events = ringed('db:main/watch');
      expect(events.map((e) => e['rows']), [1, 2]);
      expect(events.first['sql'], 'SELECT * FROM todos');
      expect(events.first['watch'], 1);
    });

    test('the snapshot rows ride in the details', () async {
      db.onQuery = (_, _) async => [
        {'id': 7, 'title': 'x'},
      ];
      var (panel, _) = mount(db.adapter());
      await panel.run('watch', {'sql': 'SELECT * FROM todos'});
      await Future<void>.delayed(Duration.zero);

      var peer = _Peer();
      core.attach(peer, 1);
      var event = peer.frames.singleWhere(
        (f) => f['t'] == 'event' && f['ch'] == 'db:main/watch',
      );
      var detail = details(event['e']! as int);
      expect(detail['rowCount'], 1);
      expect(((detail['rows']! as List).single as Map)['id'], 7);
    });

    test('a native watch is delegated to, not re-implemented', () async {
      var controller = StreamController<List<Map<String, Object?>>>();
      String? watched;
      var (panel, _) = mount(
        db.adapter(
          watch: (sql) {
            watched = sql;
            return controller.stream;
          },
        ),
      );
      await panel.run('watch', {'sql': 'SELECT count(*) FROM t'});
      expect(watched, 'SELECT count(*) FROM t');
      controller.add([
        {'c': 5},
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(ringed('db:main/watch').single['rows'], 1);
      expect(db.queried, isEmpty, reason: 'the adapter watch served it');
      await controller.close();
    });

    test('unwatch stops the snapshots and refuses an unknown id', () async {
      db.onQuery = (_, _) async => const [];
      var (panel, _) = mount(db.adapter());
      var id =
          ((await panel.run('watch', {'sql': 'SELECT 1'}))! as Map)['watch'];
      await Future<void>.delayed(Duration.zero);

      expect(await panel.run('unwatch', {'id': id}), {'stopped': id});
      db.updates.add({'todos'});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(ringed('db:main/watch'), hasLength(1), reason: 'only the initial');

      await expectLater(
        () => panel.run('unwatch', {'id': 99}),
        throwsA(
          isA<ArgumentError>().having((e) => '$e', 'message', contains('99')),
        ),
      );
    });

    test('a failing watch reports the error on the feed and stops', () async {
      db.onQuery = (_, _) async => throw StateError('no such table: nope');
      var (panel, _) = mount(db.adapter());
      await panel.run('watch', {'sql': 'SELECT * FROM nope'});
      await Future<void>.delayed(Duration.zero);

      var event = ringed('db:main/watch').single;
      expect(event['error'], contains('no such table'));
      expect(event['watch'], 1);
    });

    test('explain runs the plan for the snapshot the row belongs to', () async {
      db.onQuery = (sql, _) async => sql.startsWith('EXPLAIN')
          ? [
              {'detail': 'SCAN todos'},
            ]
          : const [];
      var (panel, _) = mount(db.adapter());
      await panel.run('watch', {'sql': 'SELECT * FROM todos'});
      await Future<void>.delayed(Duration.zero);

      var peer = _Peer();
      core.attach(peer, 1);
      var event = peer.frames.singleWhere(
        (f) => f['t'] == 'event' && f['ch'] == 'db:main/watch',
      );
      var reply = (await panel.run('explain', {'event': event['e']}))! as Map;
      expect(reply['sql'], 'SELECT * FROM todos');
      expect(((reply['rows']! as List).single as Map)['detail'], 'SCAN todos');
      expect(db.queried.last.$1, 'EXPLAIN QUERY PLAN SELECT * FROM todos');

      await expectLater(
        () => panel.run('explain', {'event': 12345}),
        throwsArgumentError,
      );
    });
  });
}

class _Peer implements InspectorPeer {
  final frames = <Map<String, Object?>>[];

  @override
  void send(Map<String, Object?> frame) => frames.add(frame);

  @override
  void close() {}
}
