import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutterware/server.dart';

import '../../address/address_scope.dart';
import '../../ui/design/tokens.dart';
import '../../ui/json_view.dart';
import '../../ui/tappable.dart';
import '../native_plugin.dart';
import 'server_address.dart';
import 'server_core.dart';

export 'server_core.dart' show ServerCore, serverPluginId;

/// The GUI half of server inspection: server chips, the request list with its
/// N+1 badges, a waterfall per request, and the raw timeline behind it all.
///
/// Everything the plugin *knows* — which servers announce themselves, their
/// events, what repeats inside a request — is in [ServerCore] and
/// [repeatedQueries], so `fw` and an agent reach the same answers. This class
/// exists because `buildPanel` returns a `Widget`.
class ServerPlugin extends NativePlugin<ServerCore> {
  ServerPlugin(super.core);

  @override
  Widget buildPanel(BuildContext context) => _ServerPanel(this);
}

/// Owns the subscription: mounting is what starts tracking. Position comes
/// from the address — `<name>/req/<eventId>` — so a request row is a place
/// search can land on and a capture can name.
class _ServerPanel extends StatefulWidget {
  const _ServerPanel(this.plugin);

  final ServerPlugin plugin;

  @override
  State<_ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<_ServerPanel> {
  ServerCore get _core => widget.plugin.core;

  @override
  void initState() {
    super.initState();
    _core.track();
  }

  ServerPlace? _resolve(BuildContext context) => serverPlace(
    [for (var i = 0; i < 3; i++) AddressScope.segment(context, i) ?? '']
      ..removeWhere((s) => s.isEmpty),
  );

  /// The tracked session the place names. By name, preferring the one still
  /// running — after a restart the stopped session and its successor share a
  /// name, and a pasted address should mean the live one.
  TrackedServer? _select(List<TrackedServer> servers, ServerPlace? place) {
    var candidates = place == null
        ? servers
        : [
            for (var server in servers)
              if (server.handle.name == place.server) server,
          ];
    if (candidates.isEmpty) candidates = servers;
    return candidates.where((s) => !s.stopped).firstOrNull ??
        candidates.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var servers = _core.servers;
        if (servers.isEmpty) return const _EmptyHint();
        var place = _resolve(context);
        var server = _select(servers, place);
        if (server == null) return const _EmptyHint();

        var events = server.events;
        // One pass: every correlated event, keyed by the request it belongs
        // to — the request list needs it for badges, the detail for spans.
        var byRid = <String, List<ServerEvent>>{};
        for (var event in events) {
          if (event.rid != null && event.channel != 'http') {
            byRid.putIfAbsent(event.rid!, () => []).add(event);
          }
        }
        var requests = [
          for (var event in events)
            if (event.channel == 'http') event,
        ];
        var selected = place?.requestId == null
            ? null
            : requests
                  .where((r) => r.id == place!.requestId)
                  .cast<ServerEvent?>()
                  .firstOrNull;

        var view = place?.view ?? ServerViewKind.overview;
        // The rail already lists every server (report.children) — repeating
        // that here for one healthy server is noise. The bar appears only
        // when it says something the rail row beside it does not: several
        // servers to switch between in place, or a session that is stopped
        // or reconnecting.
        var showBar = servers.length > 1 || server.stopped || !server.connected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBar) _ServerBar(servers, shown: server),
            _ViewTabs(server: server, view: view),
            const Divider(height: 1),
            Expanded(
              child: switch (view) {
                ServerViewKind.sql =>
                  place?.queryKey == null
                      ? _SqlView(server)
                      : _QueryDetail(
                          server: server,
                          queryKey: place!.queryKey!,
                        ),
                ServerViewKind.events => _EventTimeline(events),
                // No selection: the request list has the whole width. The raw
                // stream lives under Events, not behind an unselected detail.
                _ when selected == null => _RequestList(
                  server: server,
                  requests: requests.reversed.toList(),
                  byRid: byRid,
                  selectedId: null,
                  showTime: true,
                ),
                _ => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 380,
                      child: _RequestList(
                        server: server,
                        requests: requests.reversed.toList(),
                        byRid: byRid,
                        selectedId: selected.id,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _RequestDetail(
                        server: server,
                        request: selected,
                        caused: byRid[selected.rid] ?? const [],
                      ),
                    ),
                  ],
                ),
              },
            ),
          ],
        );
      },
    );
  }
}

class _ServerBar extends StatelessWidget {
  const _ServerBar(this.servers, {required this.shown});

  final List<TrackedServer> servers;
  final TrackedServer shown;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (var server in servers)
            Tappable.builder(
              onTap: () => AddressScope.write(
                context,
              ).setSegments(serverSegments(server.handle.name)),
              builder: (context, hovered) {
                var selected = identical(server, shown);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.accentSoft
                        : hovered
                        ? colors.hoverOverlay
                        : null,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected ? colors.accentSoft2 : colors.line,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: server.stopped
                            ? colors.mut3
                            : server.connected
                            ? colors.grn
                            : colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        server.stopped
                            ? '${server.handle.name} (stopped)'
                            : server.connected
                            ? '${server.handle.name} · pid ${server.handle.pid}'
                            : '${server.handle.name} · reconnecting',
                        style: context.type.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Requests | SQL — which pane of the shown server, written into the address.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.server, required this.view});

  final TrackedServer server;
  final ServerViewKind view;

  @override
  Widget build(BuildContext context) {
    var name = server.handle.name;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          for (var (label, segments, selected) in [
            (
              'Requests',
              serverSegments(name),
              view == ServerViewKind.overview || view == ServerViewKind.request,
            ),
            ('SQL', sqlSegments(name), view == ServerViewKind.sql),
            ('Events', eventsSegments(name), view == ServerViewKind.events),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                style: selected
                    ? TextButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                      )
                    : null,
                onPressed: () =>
                    AddressScope.write(context).setSegments(segments),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
  }
}

/// The aggregate: every query shape this server ran, heaviest first.
class _SqlView extends StatelessWidget {
  const _SqlView(this.server);

  final TrackedServer server;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var stats = sqlStats(server.events);
    if (stats.isEmpty) {
      return Center(
        child: Text('No queries recorded.', style: theme.textTheme.bodyMedium),
      );
    }
    var header = theme.textTheme.bodySmall!.copyWith(color: theme.hintColor);
    var numbers = _mono(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 50, child: Text('count', style: header)),
              Expanded(child: Text('query shape', style: header)),
              SizedBox(
                width: 70,
                child: Text('total', style: header, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 70,
                child: Text('avg', style: header, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 70,
                child: Text('max', style: header, textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        for (var shape in stats)
          Tappable.builder(
            onTap: () => AddressScope.write(
              context,
            ).setSegments(sqlSegments(server.handle.name, queryKey: shape.key)),
            builder: (context, hovered) => Container(
              color: hovered ? context.colors.hoverOverlay : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text('${shape.count}×', style: numbers),
                  ),
                  Expanded(
                    child: Text(
                      shape.normalized,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mono(context),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      _ms(shape.totalMs),
                      style: numbers,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      _ms(shape.averageMs),
                      style: numbers,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      _ms(shape.maxMs),
                      style: numbers,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One query shape: its stats, its occurrences with their parameters, and
/// the two commands that run inside the live server — explain and requery.
class _QueryDetail extends StatefulWidget {
  const _QueryDetail({required this.server, required this.queryKey});

  final TrackedServer server;
  final String queryKey;

  @override
  State<_QueryDetail> createState() => _QueryDetailState();
}

class _QueryDetailState extends State<_QueryDetail> {
  String? _resultTitle;

  /// The decoded response map on success, the error text on failure.
  Object? _result;
  var _busy = false;

  Future<void> _run(String method, String query) async {
    setState(() {
      _busy = true;
      _resultTitle = method;
      _result = null;
    });
    Object? result;
    try {
      result = await sqlCommand(widget.server, method, query);
    } on Object catch (e) {
      // A missing handler or a failing one — an answer, not a crash. The
      // hint names the fix because "no handler for sql.explain" alone reads
      // as our bug rather than a snippet not yet pasted.
      result =
          '$e\n\nThe server registers command handlers itself — see the '
          'sql adapter snippets in doc/server_inspection.md.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var stats = sqlStats(
      widget.server.events,
    ).where((s) => s.key == widget.queryKey).firstOrNull;
    if (stats == null) {
      return Center(
        child: Text(
          'This query shape is no longer in the recorded window.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    var latestQuery = stats.latest.payload['query']! as String;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                stats.normalized,
                style: _mono(context, fontSize: 15),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Back to all queries',
              onPressed: () => AddressScope.write(
                context,
              ).setSegments(sqlSegments(widget.server.handle.name)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${stats.count}× · total ${_ms(stats.totalMs)} · '
          'avg ${_ms(stats.averageMs)} · max ${_ms(stats.maxMs)}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var method in ['explain', 'requery'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  onPressed: _busy || !widget.server.connected
                      ? null
                      : () => _run(method, latestQuery),
                  child: Text(method),
                ),
              ),
            if (!widget.server.connected)
              Text('not attached', style: theme.textTheme.bodySmall),
          ],
        ),
        if (_resultTitle != null) ...[
          const SizedBox(height: 12),
          Text(_resultTitle!, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          _busy
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _CommandResult(_result),
        ],
        const SizedBox(height: 16),
        Text('Occurrences', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        // Newest first, and every one of them — the ring already bounds it.
        for (var occurrence in stats.occurrences.reversed)
          _OccurrenceRow(server: widget.server, occurrence: occurrence),
      ],
    );
  }
}

/// One raw execution: when, how long, the exact SQL and its parameters, and
/// the way back to the request that caused it.
class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({required this.server, required this.occurrence});

  final TrackedServer server;
  final ServerEvent occurrence;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var mono = _mono(context);
    var params = occurrence.payload['params'];
    var request = occurrence.rid == null
        ? null
        : server.events
              .where((e) => e.channel == 'http' && e.rid == occurrence.rid)
              .firstOrNull;
    var time = occurrence.time;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}',
            style: theme.textTheme.bodySmall!.copyWith(color: theme.hintColor),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(_ms(occurrence.payload['ms']), style: mono),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${occurrence.payload['query']}', style: mono),
                if (params != null)
                  Text(
                    'params: ${jsonEncode(params)}',
                    style: mono.copyWith(color: theme.hintColor),
                  ),
              ],
            ),
          ),
          if (request != null)
            IconButton(
              icon: const Icon(Icons.north_east, size: 14),
              tooltip:
                  '${request.payload['method']} ${request.payload['path']}',
              onPressed: () => AddressScope.write(context).setSegments(
                serverSegments(server.handle.name, requestId: request.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.server,
    required this.requests,
    required this.byRid,
    required this.selectedId,
    this.showTime = false,
  });

  final TrackedServer server;

  /// Newest first.
  final List<ServerEvent> requests;
  final Map<String, List<ServerEvent>> byRid;
  final int? selectedId;

  /// True in the full-width form, where there is room for a timestamp.
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    if (requests.isEmpty) {
      return Center(
        child: Text('No requests yet.', style: theme.textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      itemCount: requests.length,
      itemBuilder: (context, index) {
        var request = requests[index];
        var caused = request.rid == null
            ? const <ServerEvent>[]
            : byRid[request.rid] ?? const [];
        var repeated = repeatedQueries(caused);
        return _RequestRow(
          server: server,
          request: request,
          selected: request.id == selectedId,
          showTime: showTime,
          repeatedCount: repeated.isEmpty
              ? 0
              : repeated.values.reduce((a, b) => a > b ? a : b),
        );
      },
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.server,
    required this.request,
    required this.selected,
    required this.repeatedCount,
    this.showTime = false,
  });

  final TrackedServer server;
  final ServerEvent request;
  final bool selected;
  final bool showTime;

  /// The largest repeat count among this request's queries; 0 for none.
  final int repeatedCount;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var p = request.payload;
    var failed = _failed(request);
    return Tappable.builder(
      onTap: () => AddressScope.write(
        context,
      ).setSegments(serverSegments(server.handle.name, requestId: request.id)),
      builder: (context, hovered) => Container(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : hovered
            ? context.colors.hoverOverlay
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (showTime) ...[
              Text(
                _timestamp(request.time),
                style: _mono(context, color: theme.hintColor),
              ),
              const SizedBox(width: 10),
            ],
            _StatusDot(failed: failed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${p['method']} ${p['path']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(context, fontSize: 13),
              ),
            ),
            if (repeatedCount > 0) ...[
              const SizedBox(width: 6),
              Tooltip(
                message:
                    'A query repeats $repeatedCount× in this request — '
                    'the N+1 shape.',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'N+1',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Text(_ms(p['ms']), style: _mono(context, color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.circle,
    size: 8,
    color: failed ? Colors.red.shade600 : Colors.green.shade600,
  );
}

/// The selected request, in tabs: the waterfall (with its N+1 warnings),
/// its queries, the request and response messages, and its logs.
///
/// The tab is an axis (`?tab=`), not a segment — the same request seen
/// differently, which is the framework's own distinction.
class _RequestDetail extends StatelessWidget {
  const _RequestDetail({
    required this.server,
    required this.request,
    required this.caused,
  });

  final TrackedServer server;
  final ServerEvent request;
  final List<ServerEvent> caused;

  static const _tabs = ['waterfall', 'sql', 'request', 'response', 'logs'];

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var p = request.payload;
    var tab = AddressScope.param(context, 'tab') ?? 'waterfall';
    if (!_tabs.contains(tab)) tab = 'waterfall';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${p['method']} ${p['path']} → ${p['status']}',
                  style: _mono(context, fontSize: 15),
                ),
              ),
              Text(_ms(p['ms']), style: _mono(context, fontSize: 15)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Back to the request list',
                onPressed: () => AddressScope.write(
                  context,
                ).setSegments(serverSegments(server.handle.name)),
              ),
            ],
          ),
        ),
        if (p['error'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              '${p['error']}',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              for (var name in _tabs)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    style: name == tab
                        ? TextButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.1),
                          )
                        : null,
                    onPressed: () =>
                        AddressScope.write(context).setParam('tab', name),
                    child: Text(name),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (tab) {
            'sql' => _RequestSqlTab(
              server: server,
              queries: [
                for (var event in caused)
                  if (event.channel == 'sql') event,
              ],
            ),
            'request' => _HttpMessageTab(
              server: server,
              request: request,
              response: false,
            ),
            'response' => _HttpMessageTab(
              server: server,
              request: request,
              response: true,
            ),
            'logs' => _RequestLogsTab([
              for (var event in caused)
                if (event.channel == 'log') event,
            ]),
            _ => _WaterfallTab(
              server: server,
              request: request,
              caused: caused,
            ),
          },
        ),
      ],
    );
  }
}

class _WaterfallTab extends StatelessWidget {
  const _WaterfallTab({
    required this.server,
    required this.request,
    required this.caused,
  });

  final TrackedServer server;
  final ServerEvent request;
  final List<ServerEvent> caused;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var repeated = repeatedQueries(caused);
    var spans = [
      for (var event in caused)
        if (event.payload['ms'] is num) event,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var entry in repeated.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'N+1: this query runs ${entry.value}× in this request',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(entry.key, style: _mono(context)),
              ],
            ),
          ),
        _Waterfall(server: server, request: request, spans: spans),
      ],
    );
  }
}

/// The request's own queries, each expandable to its parameters, row count
/// and an inline explain — the "simple case" viewer, one tap from a request.
class _RequestSqlTab extends StatefulWidget {
  const _RequestSqlTab({required this.server, required this.queries});

  final TrackedServer server;
  final List<ServerEvent> queries;

  @override
  State<_RequestSqlTab> createState() => _RequestSqlTabState();
}

class _RequestSqlTabState extends State<_RequestSqlTab> {
  final _expanded = <int>{};
  final _explained = <int, Object?>{};
  final _busy = <int>{};

  Future<void> _explain(ServerEvent event) async {
    var query = event.payload['query']! as String;
    setState(() => _busy.add(event.id));
    Object? result;
    try {
      result = await sqlCommand(widget.server, 'explain', query);
    } on Object catch (e) {
      result =
          '$e\n\nThe server registers command handlers itself — see the '
          'sql adapter snippets in doc/server_inspection.md.';
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(event.id);
      _explained[event.id] = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var mono = _mono(context);
    if (widget.queries.isEmpty) {
      return Center(
        child: Text(
          'No queries in this request.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (var event in widget.queries) ...[
          Tappable.builder(
            onTap: () => setState(() {
              _expanded.contains(event.id)
                  ? _expanded.remove(event.id)
                  : _expanded.add(event.id);
            }),
            builder: (context, hovered) => Container(
              color: hovered ? context.colors.hoverOverlay : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _expanded.contains(event.id)
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    size: 16,
                    color: theme.hintColor,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${event.payload['query']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono,
                    ),
                  ),
                  if (event.payload['rows'] is int) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${event.payload['rows']} rows',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(_ms(event.payload['ms']), style: mono),
                ],
              ),
            ),
          ),
          if (_expanded.contains(event.id))
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('${event.payload['query']}', style: mono),
                  if (event.payload['params'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'params: ${jsonEncode(event.payload['params'])}',
                        style: mono.copyWith(color: theme.hintColor),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed:
                            _busy.contains(event.id) || !widget.server.connected
                            ? null
                            : () => _explain(event),
                        child: const Text('explain'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () =>
                            AddressScope.write(context).setSegments(
                              sqlSegments(
                                widget.server.handle.name,
                                queryKey: queryShapeKey(
                                  normalizeSql(
                                    event.payload['query']! as String,
                                  ),
                                ),
                              ),
                            ),
                        child: const Text('all occurrences'),
                      ),
                    ],
                  ),
                  if (_busy.contains(event.id))
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ),
                  if (_explained[event.id] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _CommandResult(_explained[event.id]),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// An explain/requery answer: structured responses fold like any JSON, an
/// error reads as text.
class _CommandResult extends StatelessWidget {
  const _CommandResult(this.result);

  final Object? result;

  @override
  Widget build(BuildContext context) {
    var result = this.result;
    if (result is Map || result is List) {
      return JsonView(
        data: result,
        initialExpandDepth: 3,
        searchable: false,
        maxHeight: 360,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText('$result', style: _mono(context)),
    );
  }
}

/// One side of the HTTP exchange: headers and body, fetched lazily from the
/// server's detail store the first time this tab opens.
class _HttpMessageTab extends StatelessWidget {
  const _HttpMessageTab({
    required this.server,
    required this.request,
    required this.response,
  });

  final TrackedServer server;
  final ServerEvent request;

  /// False for the request side, true for the response side.
  final bool response;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var mono = _mono(context);
    return FutureBuilder(
      future: server.detailsFor(request),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        var details = snapshot.data;
        var headers = details?[response ? 'responseHeaders' : 'requestHeaders'];
        var body = details?[response ? 'responseBody' : 'requestBody'];
        if (details == null || headers is! Map) {
          return Center(
            child: Text(
              'Not captured.\n'
              'The middleware decides what to record — see the capturing '
              'version in doc/server_inspection.md.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Headers', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (var entry in headers.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: SelectableText(
                  '${entry.key}: ${entry.value}',
                  style: mono,
                ),
              ),
            const SizedBox(height: 16),
            Text('Body', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            body is! String
                ? Text(
                    'Not captured — binary, streamed, or over the size cap.',
                    style: theme.textTheme.bodySmall,
                  )
                // A JSON body folds; anything else stays plain text. Sniffing
                // the first character beats trusting content-type, which lies.
                : body.trimLeft().startsWith(RegExp(r'[\[{]'))
                ? JsonView.source(body, maxHeight: 520)
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(body, style: mono),
                  ),
          ],
        );
      },
    );
  }
}

class _RequestLogsTab extends StatelessWidget {
  const _RequestLogsTab(this.logs);

  final List<ServerEvent> logs;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var mono = _mono(context);
    if (logs.isEmpty) {
      return Center(
        child: Text(
          'No logs in this request.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var log in logs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(_summary(log), style: mono),
          ),
      ],
    );
  }
}

/// Spans as bars over the request's duration.
///
/// An event carries its *end* (the event time) and its duration, so each bar
/// is `[time - ms, time]`, laid out against the request's own interval and
/// clamped — clock skew between an event and its request is possible and must
/// not push a bar off the canvas.
class _Waterfall extends StatelessWidget {
  const _Waterfall({
    required this.server,
    required this.request,
    required this.spans,
  });

  final TrackedServer server;
  final ServerEvent request;
  final List<ServerEvent> spans;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var requestMs = (request.payload['ms'] as num?)?.toDouble() ?? 0;
    var end = request.time.millisecondsSinceEpoch.toDouble();
    var start = end - requestMs;
    var total = requestMs <= 0 ? 1.0 : requestMs;

    Widget row(String label, double fromMs, double widthMs, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 260,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  var left =
                      (fromMs / total).clamp(0.0, 1.0) * constraints.maxWidth;
                  var width =
                      (widthMs / total).clamp(0.0, 1.0) * constraints.maxWidth;
                  return Stack(
                    children: [
                      Container(height: 14),
                      Positioned(
                        left: left,
                        width: width < 2 ? 2 : width,
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Waterfall', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        row(
          'request (${_ms(request.payload['ms'])})',
          0,
          total,
          Colors.blue.shade300,
        ),
        for (var span in spans)
          // A sql span is a door into its shape's detail — same query, seen
          // from the aggregate side.
          Tappable.builder(
            onTap: span.channel != 'sql' || span.payload['query'] is! String
                ? null
                : () => AddressScope.write(context).setSegments(
                    sqlSegments(
                      server.handle.name,
                      queryKey: queryShapeKey(
                        normalizeSql(span.payload['query']! as String),
                      ),
                    ),
                  ),
            builder: (context, hovered) => Container(
              color: hovered ? context.colors.hoverOverlay : null,
              child: row(
                _summary(span),
                ((span.time.millisecondsSinceEpoch -
                            (span.payload['ms']! as num)) -
                        start)
                    .toDouble(),
                (span.payload['ms']! as num).toDouble(),
                span.channel == 'sql'
                    ? Colors.teal.shade400
                    : Colors.purple.shade300,
              ),
            ),
          ),
      ],
    );
  }
}

/// The per-server flat timeline — what the panel shows when no request is
/// selected, so events outside any request (startup logs, background work)
/// stay visible.
class _EventTimeline extends StatelessWidget {
  const _EventTimeline(this.events);

  final List<ServerEvent> events;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    if (events.isEmpty) {
      return Center(
        child: Text(
          'Attached — waiting for events.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    var reversed = events.reversed.toList();
    return ListView.builder(
      itemCount: reversed.length,
      itemBuilder: (context, index) => _EventRow(reversed[index]),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.event);

  final ServerEvent event;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(
            _timestamp(event.time),
            style: _mono(context, color: theme.hintColor),
          ),
          const SizedBox(width: 8),
          _ChannelChip(event),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _summary(event),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono(context, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip(this.event);

  final ServerEvent event;

  @override
  Widget build(BuildContext context) {
    var failed = _failed(event);
    var color = failed
        ? Colors.red
        : switch (event.channel) {
            'http' => Colors.blue,
            'sql' => Colors.teal,
            'log' => Colors.grey,
            _ => Colors.purple,
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        event.channel,
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: color.shade700),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No servers are announcing themselves under this worktree.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Report from one with package:flutterware/server.dart — an event,\n'
            'a span or a handler is enough; it publishes on first use.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

bool _failed(ServerEvent event) =>
    event.payload['error'] != null ||
    switch (event.payload['status']) {
      int status => status >= 500,
      _ => false,
    };

String _summary(ServerEvent event) {
  var p = event.payload;
  return switch (event.channel) {
    'http' => '${p['method']} ${p['path']} → ${p['status']} (${_ms(p['ms'])})',
    'sql' => '${p['query']} (${_ms(p['ms'])})',
    'log' => '${p['level']}: ${p['message']}',
    _ => p.toString(),
  };
}

String _ms(Object? value) =>
    value is num ? '${value.toStringAsFixed(1)}ms' : '';

/// The panel's one mono style — everything that is machine data (paths,
/// queries, headers, durations) wears it; prose stays in the UI face.
TextStyle _mono(BuildContext context, {Color? color, double? fontSize}) =>
    Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      letterSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color,
      fontSize: fontSize,
    );

String _timestamp(DateTime time) =>
    '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}'
    '.${time.millisecond.toString().padLeft(3, '0')}';

String _two(int n) => n.toString().padLeft(2, '0');

extension<T> on Iterable<T> {
  T? get firstOrNull {
    var it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
