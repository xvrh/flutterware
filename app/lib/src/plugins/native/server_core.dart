import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware/server.dart';
import 'package:meta/meta.dart';

import '../../utils/run_dir.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const serverPluginId = 'flutterware.server';

/// The servers currently announcing themselves under this worktree.
///
/// Discovery is a run-dir scan for `srv-*.json` handles whose project root
/// sits inside the worktree — file reads, nothing else, so it fits
/// [computeAll]'s budget and `fw status` can call it freely. *Attaching* —
/// opening the socket, replaying the ring — happens on subscription
/// ([track], called when the panel mounts) or inside an action, per the
/// no-sockets rule in [PluginCore.computeAll].
class ServerCore extends PluginCore {
  ServerCore(super.host);

  /// Where discovery looks. A seam for tests, which point it at a temp dir
  /// instead of the developer's real run dir.
  @visibleForTesting
  static String Function() runDirProvider = flutterwareRunDir;

  final _servers = <String, TrackedServer>{};
  var _scanned = false;
  var _tracking = false;
  StreamSubscription<FileSystemEvent>? _dirWatch;
  Timer? _rescanDebounce;

  /// Servers, newest first — what the panel draws.
  List<TrackedServer> get servers =>
      _servers.values.toList()
        ..sort((a, b) => b.handle.startedAt.compareTo(a.handle.startedAt));

  @override
  Future<void> computeAll() async {
    _scan();
  }

  /// Starts live tracking: attach to every announced server, watch the run
  /// dir for handles appearing and disappearing. Idempotent; called by the
  /// panel on mount.
  void track() {
    if (_tracking || isDisposed) return;
    _tracking = true;
    _scan();
    var runDir = Directory(runDirProvider());
    _dirWatch = runDir.watch().listen((event) {
      if (!event.path.contains('srv-')) return;
      // Coalesce bursts: a restart is a delete + two creates.
      _rescanDebounce?.cancel();
      _rescanDebounce = Timer(const Duration(milliseconds: 100), _scan);
    });
  }

  void _scan() {
    if (isDisposed) return;
    _scanned = true;
    var handles = scanServerHandles(
      runDirProvider(),
      underRoot: host.worktree.path,
    );
    var seen = <String>{};
    for (var handle in handles) {
      var key = '${handle.name}-${handle.pid}';
      seen.add(key);
      var tracked = _servers.putIfAbsent(key, () => TrackedServer(handle));
      // Same process, fresher file: the inspector rewrites its handle when
      // the server publishes a base URL, and the row should say so.
      tracked.handle = handle;
      if (_tracking) _attach(tracked);
    }
    // A vanished handle is a stopped server: keep it on screen, greyed out,
    // only if we were attached and hold its history; drop it otherwise.
    _servers.removeWhere(
      (key, tracked) => !seen.contains(key) && tracked.events.isEmpty,
    );
    for (var entry in _servers.entries) {
      if (!seen.contains(entry.key)) entry.value.markStopped();
    }
    notifyChanged();
  }

  void _attach(TrackedServer tracked) {
    if (tracked.connected || tracked.stopped || tracked.attaching) return;
    tracked.attaching = true;
    unawaited(() async {
      var client = await attachToServer(tracked.handle);
      tracked.attaching = false;
      if (isDisposed) {
        await client?.close();
        return;
      }
      if (client == null) {
        // Dead handle — attachToServer deleted it; reflect that.
        tracked.markStopped();
        notifyChanged();
        return;
      }
      tracked.adopt(client, onEvent: notifyChanged);
      unawaited(
        client.done.then((_) {
          if (isDisposed || tracked.client != client) return;
          // A drop, not a death: the handle decides which on the next scan —
          // still there means reattach (decision 10), and the re-replay
          // dedupes against what this core already holds. Gone means the
          // scan marks it stopped.
          tracked.dropConnection();
          notifyChanged();
          _scheduleRescan();
        }),
      );
      notifyChanged();
    }());
  }

  void _scheduleRescan() {
    if (!_tracking || isDisposed) return;
    _rescanDebounce?.cancel();
    _rescanDebounce = Timer(const Duration(seconds: 1), _scan);
  }

  @override
  PluginReport get report {
    var servers = this.servers;
    var live = servers.where((s) => !s.stopped).length;
    var status = !_scanned
        ? Status.none
        : servers.isEmpty
        ? Status.neutral('no servers running')
        : live == 0
        ? Status.neutral('no servers running')
        : Status.good('$live running');
    return PluginReport(
      id: host.id,
      label: host.label,
      status: status,
      badge: live > 0
          ? StatusBadge.count(live, tone: Tone.good)
          : StatusBadge.none,
      children: [
        for (var server in servers)
          PluginChild(
            id: server.handle.name,
            label: server.handle.name,
            status: server.stopped
                ? Status.neutral('stopped')
                : Status.good(_where(server)),
          ),
      ],
      actions: [
        PluginAction(
          'requests',
          'Recent requests',
          description:
              'The latest HTTP requests a running server reported, each with '
              'the SQL queries and log lines it caused.',
          parameters: [
            _serverParameter,
            ActionParameter(
              'last',
              'Count',
              kind: ActionParameterKind.integer,
              required: false,
              defaultValue: '20',
            ),
          ],
        ),
        PluginAction(
          'errors',
          'Recent errors',
          description:
              'Failed requests (5xx or thrown), severe log lines, and any '
              'event carrying an error — each with the request it happened '
              'under.',
          parameters: [
            _serverParameter,
            ActionParameter(
              'last',
              'Count',
              kind: ActionParameterKind.integer,
              required: false,
              defaultValue: '20',
            ),
          ],
        ),
        PluginAction(
          'info',
          'Server info',
          description:
              'What a running server published about itself: base URL, '
              'environment, pages worth opening, connections (passwords '
              'masked) and config groups.',
          parameters: [_serverParameter],
        ),
        PluginAction(
          'sql',
          'Query statistics',
          description:
              'Every recorded query grouped by its normalized shape — count, '
              'total, average and max duration — heaviest first. The same '
              'aggregation the SQL panel shows.',
          parameters: [
            _serverParameter,
            ActionParameter(
              'top',
              'Shapes',
              kind: ActionParameterKind.integer,
              required: false,
              defaultValue: '20',
            ),
          ],
        ),
      ],
      view: PluginView([
        if (!_scanned)
          ViewText('Not scanned yet.')
        else if (servers.isEmpty)
          ViewText(
            'No servers are announcing themselves under this worktree.\n'
            'Report from one with package:flutterware/server.dart.',
          )
        else
          ViewItems([
            for (var server in servers)
              ViewItem(
                server.handle.name,
                detail: switch (server) {
                  _ when server.stopped => 'stopped',
                  _ when server.connected =>
                    '${_where(server)}, ${server.events.length} events',
                  _ when server.wasConnected =>
                    '${_where(server)}, reconnecting',
                  // The event count is only honest once attached — `fw`
                  // reads this without ever opening the socket.
                  _ => _where(server),
                },
              ),
          ]),
      ]),
    );
  }

  /// `pid 4242 · http://localhost:8080 · dev`, from the scan-only mirror —
  /// what both the child rows and the view items say about a live server.
  static String _where(TrackedServer server) => [
    'pid ${server.handle.pid}',
    ?server.handle.baseUrl,
    ?server.handle.environment,
  ].join(' · ');

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    var name = arguments['name'] as String?;
    return switch (actionId) {
      'requests' => _collect(name, (client) {
        return {
          'requests': _shapeRequests(
            client.received,
            _intArgument(arguments['last'], 20),
          ),
        };
      }),
      'errors' => _collect(name, (client) {
        return {
          'errors': _shapeErrors(
            client.received,
            _intArgument(arguments['last'], 20),
          ),
        };
      }),
      'sql' => _collect(name, (client) {
        return {
          'queries': _shapeSqlStats(
            client.received,
            _intArgument(arguments['top'], 20),
          ),
        };
      }),
      'info' => _collect(name, (client) {
        return {'info': _shapeInfo(ServerInfo.fromEvents(client.received))};
      }),
      _ => super.invoke(actionId),
    };
  }

  /// One ephemeral attachment per matching server: replay the ring, let
  /// [shape] reduce it, leave. What all three read actions share.
  Future<Object?> _collect(
    String? name,
    Map<String, Object?> Function(ServerAttachClient client) shape,
  ) async {
    var handles = scanServerHandles(
      runDirProvider(),
      underRoot: host.worktree.path,
    );
    if (name != null) {
      handles = [
        for (var handle in handles)
          if (handle.name == name) handle,
      ];
    }
    if (handles.isEmpty) {
      return {
        'servers': <Object>[],
        'note': name == null
            ? 'No servers are announcing themselves under this worktree.'
            : 'No server named "$name" is announcing itself.',
      };
    }

    var out = <Map<String, Object?>>[];
    for (var handle in handles) {
      var client = await attachToServer(handle);
      if (client == null) continue;
      try {
        await _replayed(client);
        out.add({'name': handle.name, 'pid': handle.pid, ...shape(client)});
      } finally {
        await client.close();
      }
    }
    return {'servers': out};
  }

  static int _intArgument(Object? value, int fallback) => switch (value) {
    int n => n,
    String s => int.tryParse(s) ?? fallback,
    _ => fallback,
  };

  static Future<void> _replayed(ServerAttachClient client) async {
    var deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!client.replayComplete && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// One entry per `http` event, newest first, with everything sharing its
  /// correlation id nested under it — the agent-readable waterfall.
  static List<Map<String, Object?>> _shapeRequests(
    List<ServerEvent> events,
    int last,
  ) {
    var byRid = <String, List<ServerEvent>>{};
    for (var event in events) {
      if (event.rid != null && event.channel != 'http') {
        byRid.putIfAbsent(event.rid!, () => []).add(event);
      }
    }
    var requests = events.where((e) => e.channel == 'http').toList();
    var recent = requests.length > last
        ? requests.sublist(requests.length - last)
        : requests;
    return [
      for (var request in recent.reversed)
        {
          'time': request.time.toIso8601String(),
          ...request.payload,
          if (request.rid != null && byRid[request.rid] != null)
            'caused': [
              for (var event in byRid[request.rid]!)
                {'channel': event.channel, ...event.payload},
            ],
        },
    ];
  }

  /// Anything that went wrong, newest first: failed requests, severe logs,
  /// and any event carrying an error — with the request it happened under,
  /// because "what broke" is only half the question.
  static List<Map<String, Object?>> _shapeErrors(
    List<ServerEvent> events,
    int last,
  ) {
    var requestsByRid = <String, ServerEvent>{};
    for (var event in events) {
      if (event.channel == 'http' && event.rid != null) {
        requestsByRid[event.rid!] = event;
      }
    }
    var errors = [
      for (var event in events)
        if (_isError(event)) event,
    ];
    var recent = errors.length > last
        ? errors.sublist(errors.length - last)
        : errors;
    return [
      for (var event in recent.reversed)
        {
          'time': event.time.toIso8601String(),
          'channel': event.channel,
          ...event.payload,
          if (event.channel != 'http' &&
              event.rid != null &&
              requestsByRid[event.rid] != null)
            'request': {
              'method': requestsByRid[event.rid]!.payload['method'],
              'path': requestsByRid[event.rid]!.payload['path'],
              'status': requestsByRid[event.rid]!.payload['status'],
            },
        },
    ];
  }

  static bool _isError(ServerEvent event) {
    if (event.payload['error'] != null) return true;
    if (event.channel == 'http') {
      return switch (event.payload['status']) {
        int status => status >= 500,
        _ => false,
      };
    }
    if (event.channel == 'log') {
      return const {'SEVERE', 'SHOUT'}.contains(event.payload['level']);
    }
    return false;
  }

  /// The published self-description, for eyes that are not the panel's: links
  /// resolved to absolute URLs where possible, DSN passwords and secret-like
  /// config values masked — action output ends up in terminals and agent
  /// transcripts, where there is no reveal click.
  static Map<String, Object?> _shapeInfo(ServerInfo info) {
    if (info.isEmpty) {
      return {
        'note':
            'Nothing published. The server can describe itself with '
            'FlutterwareServer.info (package:flutterware/server.dart).',
      };
    }
    return {
      if (info.baseUrl != null) 'baseUrl': info.baseUrl,
      if (info.environment != null) 'environment': info.environment,
      if (info.links != null)
        'links': [
          for (var link in info.links!)
            {
              'label': link.label,
              'url':
                  resolveLinkUrl(link.url, baseUrl: info.baseUrl) ?? link.url,
              'description': ?link.description,
            },
        ],
      if (info.connections != null)
        'connections': [
          for (var connection in info.connections!)
            {
              'kind': connection.kind,
              'label': ?connection.label,
              'dsn': maskDsn(connection.dsn),
            },
        ],
      if (info.config != null)
        'config': {
          for (var group in info.config!.entries)
            group.key: {
              for (var entry in group.value.entries)
                entry.key: isSecretLikeKey(entry.key) ? '••••' : entry.value,
            },
        },
    };
  }

  /// [sqlStats], flattened for the wire — same aggregation the panel shows.
  static List<Map<String, Object?>> _shapeSqlStats(
    List<ServerEvent> events,
    int top,
  ) => [
    for (var shape in sqlStats(events).take(top))
      {
        'query': shape.normalized,
        'count': shape.count,
        'totalMs': double.parse(shape.totalMs.toStringAsFixed(1)),
        'avgMs': double.parse(shape.averageMs.toStringAsFixed(1)),
        'maxMs': double.parse(shape.maxMs.toStringAsFixed(1)),
      },
  ];

  @override
  void dispose() {
    _rescanDebounce?.cancel();
    unawaited(_dirWatch?.cancel());
    for (var tracked in _servers.values) {
      tracked.dispose();
    }
    super.dispose();
  }
}

/// One announced server: its handle, the live attachment when tracking, and
/// the events seen so far — which outlive both the connection and the
/// server, so a drop or a crash never loses history mid-investigation.
class TrackedServer {
  TrackedServer(this.handle);

  /// Refreshed on every scan — the same process rewrites its handle file
  /// when it learns its base URL, and the identity key (`name-pid`) is
  /// what stays fixed.
  ServerHandle handle;
  ServerAttachClient? client;
  StreamSubscription<ServerEvent>? _eventSubscription;
  var attaching = false;
  var stopped = false;

  /// Distinguishes "dropped, reattaching" from "never attached" — `fw`, which
  /// only scans, must not report a server it never touched as reconnecting.
  var wasConnected = false;

  bool get connected => client != null;

  /// This core's own copy, merged across attachments and deduped by event id
  /// (monotonic per server process — decision 10). A reattach replays the
  /// whole ring; everything already here collapses to a no-op.
  List<ServerEvent> get events => List.unmodifiable(_events);
  final _events = <ServerEvent>[];
  var _lastEventId = 0;

  /// The latest self-description this server published — computed from the
  /// events like [sqlStats], so it survives drops and restarts with them.
  ServerInfo get info => ServerInfo.fromEvents(_events);

  /// Takes ownership of a fresh attachment. Subscribes before draining
  /// [ServerAttachClient.received] so nothing can slip between the two; the
  /// id check makes the overlap harmless.
  void adopt(ServerAttachClient attached, {required void Function() onEvent}) {
    client = attached;
    wasConnected = true;
    _eventSubscription = attached.events.listen((event) {
      _absorb(event);
      onEvent();
    });
    for (var event in attached.received) {
      _absorb(event);
    }
  }

  void _absorb(ServerEvent event) {
    if (event.id <= _lastEventId) return;
    _lastEventId = event.id;
    _events.add(event);
  }

  /// One event's lazy details — headers, bodies — fetched once and kept.
  ///
  /// Null means the server never captured them, evicted them, or is gone;
  /// the panel words those the same way ("not captured"), because the
  /// difference is not actionable from here. Cached including the nulls: a
  /// detail that was evicted once will not un-evict.
  Future<Map<String, Object?>?> detailsFor(ServerEvent event) {
    return _detailsCache.putIfAbsent(event.id, () async {
      var client = this.client;
      if (client == null) return null;
      try {
        return await client.details(event.id);
      } on Object {
        return null;
      }
    });
  }

  final _detailsCache = <int, Future<Map<String, Object?>?>>{};

  /// The connection is gone; the server may not be. Keeps the history and
  /// [wasConnected], so the next scan can reattach or conclude "stopped".
  void dropConnection() {
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    var dropped = client;
    client = null;
    if (dropped != null) unawaited(dropped.close());
  }

  void markStopped() {
    stopped = true;
    dropConnection();
  }

  void dispose() => markStopped();
}

/// A curl invocation reproducing [request], or null when one cannot be built
/// — no published `baseUrl` to make the URL absolute, or no recorded path.
///
/// Headers and body come from the event's lazy details when captured. `host`
/// and `content-length` are dropped because curl derives them; values the
/// middleware redacted come through as `<redacted>` — a placeholder the user
/// edits, deliberately visible rather than silently missing.
String? curlCommand(
  ServerInfo info,
  ServerEvent request, {
  Map<String, Object?>? details,
}) {
  var path = request.payload['path'];
  if (path is! String) return null;
  var url = info.baseUrl == null
      ? null
      : resolveLinkUrl(path, baseUrl: info.baseUrl);
  if (url == null) return null;
  var method = request.payload['method'];
  var methodFlag = method is String && method != 'GET' ? ' -X $method' : '';
  var lines = ['curl$methodFlag ${_shellQuote(url)}'];
  var headers = details?['requestHeaders'];
  if (headers is Map) {
    for (var entry in headers.entries) {
      var name = '${entry.key}'.toLowerCase();
      if (name == 'host' || name == 'content-length') continue;
      lines.add('-H ${_shellQuote('${entry.key}: ${entry.value}')}');
    }
  }
  var body = details?['requestBody'];
  if (body is String && body.isNotEmpty) {
    lines.add('--data-raw ${_shellQuote(body)}');
  }
  return lines.join(' \\\n  ');
}

String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Sends a `sql` command — `explain`, `requery` — into a live server, which
/// runs it on its own connection and answers. Throws [StateError] when not
/// attached and [ServerRequestException] when the server has no such handler
/// or the handler failed; the panel shows both as text, not as crashes.
Future<Map<String, Object?>> sqlCommand(
  TrackedServer server,
  String method,
  String query,
) {
  var client = server.client;
  if (client == null) {
    throw StateError('Not attached to ${server.handle.name}.');
  }
  return client.request('sql', method, {'query': query});
}

/// One normalized query shape, aggregated across everything a server
/// reported — the row of the SQL view.
class QueryStats {
  QueryStats(this.normalized) : key = queryShapeKey(normalized);

  final String normalized;

  /// The address segment naming this shape — see `server_address.dart`.
  final String key;

  final occurrences = <ServerEvent>[];
  var totalMs = 0.0;
  var maxMs = 0.0;

  int get count => occurrences.length;
  double get averageMs => count == 0 ? 0 : totalMs / count;

  /// The most recent raw occurrence — what explain and requery act on: a
  /// real query the database has actually seen, not the `?`-shape.
  ServerEvent get latest => occurrences.last;
}

/// The stable identity of a normalized shape, short enough for a segment.
String queryShapeKey(String normalized) =>
    sha1.convert(utf8.encode(normalized)).toString().substring(0, 8);

/// Every `sql` event grouped by shape, heaviest total time first — the whole
/// SQL view, computed rather than stored, so it is always the events' truth.
/// On the core side so the panel and whatever `fw` reports later agree.
List<QueryStats> sqlStats(Iterable<ServerEvent> events) {
  var byShape = <String, QueryStats>{};
  for (var event in events) {
    if (event.channel != 'sql') continue;
    var query = event.payload['query'];
    if (query is! String) continue;
    var stats = byShape.putIfAbsent(
      normalizeSql(query),
      () => QueryStats(normalizeSql(query)),
    );
    stats.occurrences.add(event);
    var ms = event.payload['ms'];
    if (ms is num) {
      stats.totalMs += ms.toDouble();
      if (ms > stats.maxMs) stats.maxMs = ms.toDouble();
    }
  }
  return byShape.values.toList()
    ..sort((a, b) => b.totalMs.compareTo(a.totalMs));
}

/// Normalized query → occurrence count, for queries repeated at least
/// [threshold] times within one request's correlated events — the N+1 shape.
///
/// Counts on [normalizeSql]'s output because the N+1 queries differ precisely
/// in their literals (spec decision 12). Lives on the core side so the badge
/// the panel draws and whatever `fw` reports later are the same computation.
Map<String, int> repeatedQueries(
  Iterable<ServerEvent> caused, {
  int threshold = 3,
}) {
  var counts = <String, int>{};
  for (var event in caused) {
    if (event.channel != 'sql') continue;
    var query = event.payload['query'];
    if (query is! String) continue;
    counts.update(normalizeSql(query), (n) => n + 1, ifAbsent: () => 1);
  }
  counts.removeWhere((_, count) => count < threshold);
  return counts;
}

const _serverParameter = ActionParameter(
  'name',
  'Server',
  required: false,
  description: 'Which server, when several are running.',
);

PluginCore serverCoreFactory(PluginHost host) => ServerCore(host);
