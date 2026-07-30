import 'dart:async';
import 'dart:io';

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
                : Status.good('pid ${server.handle.pid}'),
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
            ActionParameter(
              'name',
              'Server',
              required: false,
              description: 'Which server, when several are running.',
            ),
            ActionParameter(
              'last',
              'Count',
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
                detail: server.stopped
                    ? 'stopped'
                    : server.connected
                    ? 'pid ${server.handle.pid}, '
                          '${server.events.length} events'
                    : server.wasConnected
                    ? 'pid ${server.handle.pid}, reconnecting'
                    // The event count is only honest once attached — `fw`
                    // reads this without ever opening the socket.
                    : 'pid ${server.handle.pid}',
              ),
          ]),
      ]),
    );
  }

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    if (actionId != 'requests') return super.invoke(actionId);
    var name = arguments['name'] as String?;
    var last = switch (arguments['last']) {
      int n => n,
      String s => int.tryParse(s) ?? 20,
      _ => 20,
    };

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

    // An ephemeral attachment per server: replay the ring, shape it, leave.
    var out = <Map<String, Object?>>[];
    for (var handle in handles) {
      var client = await attachToServer(handle);
      if (client == null) continue;
      try {
        await _replayed(client);
        out.add({
          'name': handle.name,
          'pid': handle.pid,
          'requests': _shapeRequests(client.received, last),
        });
      } finally {
        await client.close();
      }
    }
    return {'servers': out};
  }

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

  final ServerHandle handle;
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

PluginCore serverCoreFactory(PluginHost host) => ServerCore(host);
