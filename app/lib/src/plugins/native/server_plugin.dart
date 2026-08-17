import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/server.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../address/address_scope.dart';
import '../../inspect/inspect_dock.dart';
import '../../ui/json_view.dart';
import '../../ui/panel_header.dart';
import '../../ui/tappable.dart';
import '../native_plugin.dart';
import 'server_address.dart';
import 'server_core.dart';
import '../../ui/design/design.dart';
import '../../ui/loading_state.dart';
import '../../ui/empty_state.dart';

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

  /// Mounting starts tracking, and a config reload is not a mount: the session
  /// is rebuilt under a panel that keeps its position, so this `State` is
  /// reused and the new core is never tracked. The panel then reports on a
  /// core nothing has ever looked at.
  @override
  void didUpdateWidget(_ServerPanel old) {
    super.didUpdateWidget(old);
    if (old.plugin != widget.plugin) _core.track();
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
        var info = server.info;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FwPanelHeader(
              server.handle.name,
              badge: _Identity(server: server, info: info),
              subtitle: [
                'pid ${server.handle.pid}',
                if (server.stopped)
                  'no longer announcing'
                else if (!server.connected)
                  'attaching',
              ],
              trailing: info.baseUrl == null ? null : _UrlLink(info.baseUrl!),
              // The rail already lists every server, so one healthy server
              // needs no switcher. Two do: the rail row beside this one cannot
              // say which of them the panel is showing.
              below: servers.length > 1
                  ? _ServerBar(servers, shown: server)
                  : null,
              toolbar: _ViewTabs(
                server: server,
                view: view,
                requests: requests.length,
              ),
            ),
            Divider(height: 1, color: context.colors.line),
            Expanded(
              child: switch (view) {
                ServerViewKind.sql =>
                  place?.queryKey == null
                      ? _SqlView(server)
                      : _QueryDetail(
                          server: server,
                          queryKey: place!.queryKey!,
                        ),
                ServerViewKind.info => _InfoView(info: info),
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

/// What the panel is showing, beside its name: the session's state and, when
/// the server declared one, the environment it is pointed at.
class _Identity extends StatelessWidget {
  const _Identity({required this.server, required this.info});

  final TrackedServer server;
  final ServerInfo info;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _StatePill(server),
      if (info.environment case var it?) ...[
        const Gap(FwSpacing.sm),
        _EnvironmentChip(it),
      ],
    ],
  );
}

/// Running, attaching, or gone — the one thing a row of numbers cannot say.
class _StatePill extends StatelessWidget {
  const _StatePill(this.server);

  final TrackedServer server;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var (label, color) = server.stopped
        ? ('stopped', colors.mut3)
        : server.connected
        ? ('running', colors.grn)
        : ('reconnecting', colors.amber);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Text(
        label,
        style: context.type.micro.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
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
    return Wrap(
      spacing: FwSpacing.md,
      runSpacing: FwSpacing.xs,
      children: [
        for (var server in servers)
          Tappable(
            onTap: () => AddressScope.write(
              context,
            ).setSegments(serverSegments(server.handle.name)),
            borderRadius: BorderRadius.circular(context.radii.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FwSpacing.lg,
                vertical: FwSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: identical(server, shown) ? colors.accentSoft : null,
                borderRadius: BorderRadius.circular(context.radii.pill),
                border: Border.all(
                  color: identical(server, shown)
                      ? colors.accentSoft2
                      : colors.line,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: FwIconSize.xs - 4,
                    color: server.stopped
                        ? colors.mut3
                        : server.connected
                        ? colors.grn
                        : colors.amber,
                  ),
                  const Gap(FwSpacing.sm),
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
            ),
          ),
      ],
    );
  }
}

/// Requests | SQL | Info | Events — which pane of the shown server, written
/// into the address.
///
/// [InspectTabStrip] rather than a row of `TextButton`s, for the reason the run
/// cockpit swapped first: this was the app's second hand-rolled strip, and two
/// panels showing tabs in two designs is a difference the reader has to spend
/// attention ruling out. Which server, and where it points, moved up into the
/// header — it is context for every pane, not a member of the strip.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.server,
    required this.view,
    required this.requests,
  });

  final TrackedServer server;
  final ServerViewKind view;

  /// Badged on the Requests tab. Free — the panel counted them to draw the
  /// list. The SQL count deliberately is not: it costs a normalisation pass
  /// over every event, which is not a thing to pay for on every frame.
  final int requests;

  @override
  Widget build(BuildContext context) {
    var name = server.handle.name;
    var current = switch (view) {
      ServerViewKind.overview || ServerViewKind.request => 'requests',
      ServerViewKind.sql => 'sql',
      ServerViewKind.info => 'info',
      ServerViewKind.events => 'events',
    };
    return InspectTabStrip(
      tabs: [
        InspectDockTab(
          id: 'requests',
          label: 'Requests',
          badge: requests,
          body: _unused,
        ),
        const InspectDockTab(id: 'sql', label: 'SQL', body: _unused),
        const InspectDockTab(id: 'info', label: 'Info', body: _unused),
        const InspectDockTab(id: 'events', label: 'Events', body: _unused),
      ],
      current: current,
      onSelect: (id) => AddressScope.write(context).setSegments(switch (id) {
        'sql' => sqlSegments(name),
        'info' => infoSegments(name),
        'events' => eventsSegments(name),
        _ => serverSegments(name),
      }),
    );
  }

  /// The strip reads ids, labels and badges and never builds a body — the
  /// panel keeps its panes, which are switched on the address.
  static Widget _unused(BuildContext context) => const SizedBox.shrink();
}

/// [InspectTabStrip] over a plain id → label map, for the request detail's own
/// strip. The panel has two strips and they must not drift apart again.
class _InspectStrip extends StatelessWidget {
  const _InspectStrip({
    required this.tabs,
    required this.current,
    required this.onSelect,
    this.badges = const {},
  });

  final Map<String, String> tabs;
  final String current;
  final Map<String, int> badges;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => InspectTabStrip(
    tabs: [
      for (var tab in tabs.entries)
        InspectDockTab(
          id: tab.key,
          label: tab.value,
          badge: badges[tab.key] ?? 0,
          body: _ViewTabs._unused,
        ),
    ],
    current: current,
    onSelect: onSelect,
  );
}

/// The declared environment, colored by how much it should worry you: quiet
/// for dev-shaped names, loud for production-shaped ones — an inspector
/// forced on with `FW_SERVER_INSPECT=1` should say where it is pointed.
class _EnvironmentChip extends StatelessWidget {
  const _EnvironmentChip(this.environment);

  final String environment;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var lower = environment.toLowerCase();
    var color = const {'prod', 'production', 'live'}.contains(lower)
        ? colors.red
        : const {'dev', 'development', 'local', 'debug', 'test'}.contains(lower)
        ? colors.mut
        : colors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(context.radii.micro),
      ),
      child: Text(
        environment,
        style: context.type.micro.copyWith(color: color),
      ),
    );
  }
}

/// A heading inside a pane — *Headers*, *Occurrences*, *Links*.
///
/// Uppercase `fieldLabel`, which is what the dev stack's panel next door
/// already uses for the same job. These were Material's `titleSmall`: a
/// sentence-case 14 px semibold that reads as a title rather than as a label,
/// and is the only such face in the app.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: context.type.fieldLabel.copyWith(color: context.colors.mut),
  );
}

/// An absolute URL as a clickable piece of text.
class _UrlLink extends StatelessWidget {
  const _UrlLink(this.url, {this.label});

  final String url;

  /// Shown instead of the URL itself when given.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Tappable.builder(
      onTap: () => launchUrl(Uri.parse(url)),
      builder: (context, hovered) => Text(
        label ?? url,
        style: context.type.mono.copyWith(
          color: context.colors.accent,
          decoration: hovered ? TextDecoration.underline : null,
        ),
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
    var stats = sqlStats(server.events);
    if (stats.isEmpty) {
      return const EmptyState(
        icon: Icons.storage_outlined,
        title: 'No queries recorded',
      );
    }
    var header = context.type.micro.copyWith(color: context.colors.mut2);
    var numbers = context.type.mono;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: panelGutter,
            vertical: FwSpacing.xs,
          ),
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
        Divider(height: 1, color: context.colors.line),
        for (var shape in stats)
          Tappable(
            onTap: () => AddressScope.write(
              context,
            ).setSegments(sqlSegments(server.handle.name, queryKey: shape.key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: panelGutter,
                vertical: FwSpacing.sm,
              ),
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
                      style: context.type.mono,
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

  Future<void> _run(String method, ServerEvent occurrence) async {
    setState(() {
      _busy = true;
      _resultTitle = method;
      _result = null;
    });
    Object? result;
    try {
      result = await sqlCommand(widget.server, method, occurrence);
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
    var colors = context.colors;
    var stats = sqlStats(
      widget.server.events,
    ).where((s) => s.key == widget.queryKey).firstOrNull;
    if (stats == null) {
      return const EmptyState(
        icon: Icons.history_toggle_off,
        title: 'Outside the recorded window',
        message: 'This query shape is no longer being kept.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(panelGutter),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                stats.normalized,
                style: context.type.mono.copyWith(fontSize: 14),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: FwIconSize.lg),
              tooltip: 'Back to all queries',
              onPressed: () => AddressScope.write(
                context,
              ).setSegments(sqlSegments(widget.server.handle.name)),
            ),
          ],
        ),
        const Gap(FwSpacing.xs),
        Text(
          '${stats.count}× · total ${_ms(stats.totalMs)} · '
          'avg ${_ms(stats.averageMs)} · max ${_ms(stats.maxMs)}',
          style: context.type.caption,
        ),
        const Gap(FwSpacing.lg),
        Row(
          children: [
            for (var method in ['explain', 'requery'])
              Padding(
                padding: const EdgeInsets.only(right: FwSpacing.md),
                child: OutlinedButton(
                  onPressed: _busy || !widget.server.connected
                      ? null
                      // The latest occurrence, which is a statement the
                      // database has really seen — the `?`-shape above it is a
                      // grouping key and would not run.
                      : () => _run(method, stats.latest),
                  child: Text(method),
                ),
              ),
            if (!widget.server.connected)
              Text(
                'not attached',
                style: context.type.caption.copyWith(color: colors.mut2),
              ),
          ],
        ),
        if (_resultTitle != null) ...[
          const Gap(FwSpacing.lg),
          _SectionLabel(_resultTitle!),
          const Gap(FwSpacing.xs),
          _busy
              ? const Padding(
                  padding: EdgeInsets.all(FwSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _CommandResult(_result),
        ],
        const Gap(FwSpacing.xl),
        const _SectionLabel('Occurrences'),
        const Gap(FwSpacing.xs),
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
    var colors = context.colors;
    var mono = context.type.mono;
    var params = occurrence.payload['params'];
    var request = occurrence.rid == null
        ? null
        : server.events
              .where((e) => e.channel == 'http' && e.rid == occurrence.rid)
              .firstOrNull;
    var time = occurrence.time;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}',
            style: mono.copyWith(color: colors.mut2),
          ),
          const Gap(FwSpacing.md),
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
                    style: mono.copyWith(color: colors.mut2),
                  ),
              ],
            ),
          ),
          if (request != null)
            IconButton(
              icon: const Icon(Icons.north_east, size: FwIconSize.sm),
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
    if (requests.isEmpty) {
      return const EmptyState(icon: Icons.swap_vert, title: 'No requests yet');
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
    var colors = context.colors;
    var mono = context.type.mono;
    var p = request.payload;
    var failed = _failed(request);
    return Tappable(
      onTap: () => AddressScope.write(
        context,
      ).setSegments(serverSegments(server.handle.name, requestId: request.id)),
      child: Container(
        color: selected ? colors.accentSoft : null,
        padding: EdgeInsets.symmetric(
          // The full-width list sits on the panel gutter like everything else;
          // the 380 px column beside a detail cannot afford it.
          horizontal: showTime ? panelGutter : FwSpacing.lg,
          vertical: FwSpacing.sm,
        ),
        child: Row(
          children: [
            if (showTime) ...[
              Text(
                _timestamp(request.time),
                style: mono.copyWith(color: colors.mut2),
              ),
              const Gap(FwSpacing.lg),
            ],
            _StatusDot(failed: failed),
            const Gap(FwSpacing.md),
            Expanded(
              child: Text(
                '${p['method']} ${p['path']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono,
              ),
            ),
            if (repeatedCount > 0) ...[
              const Gap(FwSpacing.sm),
              _NPlusOneBadge(repeatedCount),
            ],
            const Gap(FwSpacing.md),
            Text(_ms(p['ms']), style: mono.copyWith(color: colors.mut2)),
          ],
        ),
      ),
    );
  }
}

/// The one finding this list makes on its own: a query the request ran over
/// and over.
class _NPlusOneBadge extends StatelessWidget {
  const _NPlusOneBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tooltip(
      message: 'A query repeats $count× in this request — the N+1 shape.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.sm,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          color: colors.amber.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(context.radii.micro),
        ),
        child: Text(
          'N+1',
          style: context.type.micro.copyWith(color: colors.warningText),
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
    size: FwIconSize.xs - 4,
    color: failed ? context.colors.red : context.colors.grn,
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

  /// Ids and their labels. The ids are the address's — a link somebody pasted
  /// says `?tab=waterfall` — while the labels are the strip's, and the strip
  /// spells a label the way every other tab in the app is spelled.
  static const _tabs = {
    'waterfall': 'Waterfall',
    'sql': 'SQL',
    'request': 'Request',
    'response': 'Response',
    'logs': 'Logs',
  };

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var p = request.payload;
    var tab = AddressScope.param(context, 'tab') ?? 'waterfall';
    if (!_tabs.containsKey(tab)) tab = 'waterfall';
    var queries = [
      for (var event in caused)
        if (event.channel == 'sql') event,
    ];
    var logs = [
      for (var event in caused)
        if (event.channel == 'log') event,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.xl,
            FwSpacing.lg,
            FwSpacing.md,
            FwSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${p['method']} ${p['path']} → ${p['status']}',
                  style: context.type.mono.copyWith(fontSize: 14),
                ),
              ),
              Text(
                _ms(p['ms']),
                style: context.type.mono.copyWith(fontSize: 14),
              ),
              const Gap(FwSpacing.md),
              _CopyAsCurlButton(server: server, request: request),
              IconButton(
                icon: const Icon(Icons.close, size: FwIconSize.lg),
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
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.xl,
              0,
              FwSpacing.xl,
              FwSpacing.md,
            ),
            child: Text(
              '${p['error']}',
              style: context.type.bodySmall.copyWith(color: colors.red),
            ),
          ),
        _InspectStrip(
          tabs: _tabs,
          current: tab,
          badges: {'sql': queries.length, 'logs': logs.length},
          onSelect: (name) => AddressScope.write(context).setParam('tab', name),
        ),
        Divider(height: 1, color: colors.line),
        Expanded(
          child: switch (tab) {
            'sql' => _RequestSqlTab(server: server, queries: queries),
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
            'logs' => _RequestLogsTab(logs),
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

/// One click from "I see the request" to "I can reproduce it in a terminal":
/// copies a curl built from the event summary plus the lazily-held headers
/// and body ([curlCommand]). Needs the server to have published its base URL
/// — a relative path is not a runnable command — and says so when it has not.
class _CopyAsCurlButton extends StatelessWidget {
  const _CopyAsCurlButton({required this.server, required this.request});

  final TrackedServer server;
  final ServerEvent request;

  @override
  Widget build(BuildContext context) {
    var enabled =
        server.info.baseUrl != null && request.payload['path'] is String;
    // Wrapped manually because a disabled IconButton swallows its tooltip,
    // and the disabled state is exactly when the tooltip has to explain.
    return Tooltip(
      message: enabled
          ? 'Copy as curl'
          : 'Copy as curl — needs a published baseUrl '
                '(FlutterwareServer.info)',
      child: IconButton(
        icon: const Icon(Icons.terminal, size: FwIconSize.lg),
        onPressed: !enabled
            ? null
            : () async {
                var details = await server.detailsFor(request);
                var command = curlCommand(
                  server.info,
                  request,
                  details: details,
                );
                if (command == null) return;
                await Clipboard.setData(ClipboardData(text: command));
              },
      ),
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
    var colors = context.colors;
    var repeated = repeatedQueries(caused);
    var spans = [
      for (var event in caused)
        if (event.payload['ms'] is num) event,
    ];
    return ListView(
      padding: const EdgeInsets.all(FwSpacing.xl),
      children: [
        for (var entry in repeated.entries)
          Container(
            margin: const EdgeInsets.only(bottom: FwSpacing.lg),
            padding: const EdgeInsets.all(FwSpacing.lg),
            decoration: BoxDecoration(
              color: colors.amber.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              border: Border.all(color: colors.amber.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: FwIconSize.sm,
                    color: colors.warningText,
                  ),
                ),
                const Gap(FwSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'N+1: this query runs ${entry.value}× in this request',
                        style: context.type.bodySmall.copyWith(
                          color: colors.warningText,
                        ),
                      ),
                      const Gap(FwSpacing.xxs),
                      Text(entry.key, style: context.type.mono),
                    ],
                  ),
                ),
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
    setState(() => _busy.add(event.id));
    Object? result;
    try {
      result = await sqlCommand(widget.server, 'explain', event);
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
    var colors = context.colors;
    var mono = context.type.mono;
    if (widget.queries.isEmpty) {
      return const EmptyState(
        icon: Icons.storage_outlined,
        title: 'No queries in this request',
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
      children: [
        for (var event in widget.queries) ...[
          Tappable(
            onTap: () => setState(() {
              _expanded.contains(event.id)
                  ? _expanded.remove(event.id)
                  : _expanded.add(event.id);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FwSpacing.xl,
                vertical: FwSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded.contains(event.id)
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    size: FwIconSize.md,
                    color: colors.mut3,
                  ),
                  const Gap(FwSpacing.xs),
                  Expanded(
                    child: Text(
                      '${event.payload['query']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono,
                    ),
                  ),
                  if (event.payload['rows'] is int) ...[
                    const Gap(FwSpacing.md),
                    Text(
                      '${event.payload['rows']} rows',
                      style: context.type.caption.copyWith(color: colors.mut2),
                    ),
                  ],
                  const Gap(FwSpacing.md),
                  Text(_ms(event.payload['ms']), style: mono),
                ],
              ),
            ),
          ),
          if (_expanded.contains(event.id))
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FwSpacing.xxxl + FwSpacing.xs,
                0,
                FwSpacing.xl,
                FwSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('${event.payload['query']}', style: mono),
                  if (event.payload['params'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: FwSpacing.xxs),
                      child: Text(
                        'params: ${jsonEncode(event.payload['params'])}',
                        style: mono.copyWith(color: colors.mut2),
                      ),
                    ),
                  const Gap(FwSpacing.sm),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed:
                            _busy.contains(event.id) || !widget.server.connected
                            ? null
                            : () => _explain(event),
                        child: const Text('explain'),
                      ),
                      const Gap(FwSpacing.md),
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
                      padding: EdgeInsets.all(FwSpacing.md),
                      child: CircularProgressIndicator(),
                    ),
                  if (_explained[event.id] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: FwSpacing.sm),
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
    return _Slab(child: SelectableText('$result', style: context.type.mono));
  }
}

/// A block of machine text on the panel's own recessed surface.
///
/// Three call sites drew this by hand out of `colorScheme.surfaceContainer
/// Highest` at half alpha — a Material surface that has no relationship to the
/// palette the rest of the panel is painted from.
class _Slab extends StatelessWidget {
  const _Slab({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(FwSpacing.lg),
    decoration: BoxDecoration(
      color: context.colors.panel2,
      borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      border: Border.all(color: context.colors.line),
    ),
    child: child,
  );
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
    var mono = context.type.mono;
    return FutureBuilder(
      future: server.detailsFor(request),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingState(title: 'Reading the request…');
        }
        var details = snapshot.data;
        var headers = details?[response ? 'responseHeaders' : 'requestHeaders'];
        var body = details?[response ? 'responseBody' : 'requestBody'];
        if (details == null || headers is! Map) {
          return const EmptyState(
            icon: Icons.visibility_off_outlined,
            title: 'Not captured',
            message:
                'The middleware decides what to record — see the capturing '
                'version in doc/server_inspection.md.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(FwSpacing.xl),
          children: [
            const _SectionLabel('Headers'),
            const Gap(FwSpacing.sm),
            for (var entry in headers.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: SelectableText(
                  '${entry.key}: ${entry.value}',
                  style: mono,
                ),
              ),
            const Gap(FwSpacing.xl),
            const _SectionLabel('Body'),
            const Gap(FwSpacing.sm),
            body is! String
                ? Text(
                    'Not captured — binary, streamed, or over the size cap.',
                    style: context.type.caption.copyWith(
                      color: context.colors.mut2,
                    ),
                  )
                // A JSON body folds; anything else stays plain text. Sniffing
                // the first character beats trusting content-type, which lies.
                : body.trimLeft().startsWith(RegExp(r'[\[{]'))
                ? JsonView.source(body, maxHeight: 520)
                : _Slab(child: SelectableText(body, style: mono)),
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
    var mono = context.type.mono;
    if (logs.isEmpty) {
      return const EmptyState(
        icon: Icons.article_outlined,
        title: 'No logs in this request',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(FwSpacing.xl),
      children: [
        for (var log in logs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
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
    var colors = context.colors;
    var requestMs = (request.payload['ms'] as num?)?.toDouble() ?? 0;
    var end = request.time.millisecondsSinceEpoch.toDouble();
    var start = end - requestMs;
    var total = requestMs <= 0 ? 1.0 : requestMs;

    Widget row(String label, double fromMs, double widthMs, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
        child: Row(
          children: [
            SizedBox(
              width: 260,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.mono,
              ),
            ),
            const Gap(FwSpacing.md),
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
                            borderRadius: BorderRadius.circular(
                              context.radii.micro,
                            ),
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
        const _SectionLabel('Waterfall'),
        const Gap(FwSpacing.sm),
        // The request is the ruler the spans are read against, so it is the
        // accent; what it caused is quieter than it, and a query is told from
        // anything else by hue rather than by weight.
        row(
          'request (${_ms(request.payload['ms'])})',
          0,
          total,
          colors.accent.withValues(alpha: 0.55),
        ),
        for (var span in spans)
          // A sql span is a door into its shape's detail — same query, seen
          // from the aggregate side.
          Tappable(
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
            child: row(
              _summary(span),
              ((span.time.millisecondsSinceEpoch -
                          (span.payload['ms']! as num)) -
                      start)
                  .toDouble(),
              (span.payload['ms']! as num).toDouble(),
              span.channel == 'sql' ? colors.grn : colors.info,
            ),
          ),
      ],
    );
  }
}

/// The per-server flat timeline — what the panel shows when no request is
/// selected, so events outside any request (startup logs, background work)
/// stay visible.
/// The self-description pane — what the server published with
/// `FlutterwareServer.info`, made actionable: links open in the browser,
/// DSN passwords and secret-like config values are masked until clicked,
/// copy always copies the real value.
class _InfoView extends StatefulWidget {
  const _InfoView({required this.info});

  final ServerInfo info;

  @override
  State<_InfoView> createState() => _InfoViewState();
}

class _InfoViewState extends State<_InfoView> {
  /// What the user chose to see in the clear — masking guards screen shares,
  /// so it yields to one deliberate click, per value.
  final _revealed = <String>{};

  @override
  Widget build(BuildContext context) {
    var info = widget.info;
    if (info.isEmpty) return const _NoInfoHint();
    var links = info.links ?? const [];
    var connections = info.connections ?? const [];
    var config = info.config ?? const {};
    return ListView(
      padding: const EdgeInsets.all(panelGutter),
      children: [
        if (links.isNotEmpty) ...[
          const _SectionLabel('Links'),
          const Gap(FwSpacing.sm),
          for (var link in links) _LinkRow(link, baseUrl: info.baseUrl),
          const Gap(FwSpacing.xl),
        ],
        if (connections.isNotEmpty) ...[
          const _SectionLabel('Connections'),
          const Gap(FwSpacing.sm),
          for (var (index, connection) in connections.indexed)
            _connectionRow(context, 'conn-$index', connection),
          const Gap(FwSpacing.xl),
        ],
        for (var group in config.entries) ...[
          _SectionLabel(group.key),
          const Gap(FwSpacing.sm),
          for (var entry in group.value.entries)
            _configRow(context, '${group.key}/${entry.key}', entry),
          const Gap(FwSpacing.xl),
        ],
      ],
    );
  }

  Widget _connectionRow(
    BuildContext context,
    String key,
    ServerConnection connection,
  ) {
    var masked = maskDsn(connection.dsn);
    var secret = masked != connection.dsn;
    var revealed = _revealed.contains(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
      child: Row(
        children: [
          _KindChip(connection.kind),
          const Gap(FwSpacing.md),
          if (connection.label != null) ...[
            Text(connection.label!, style: context.type.bodySmall),
            const Gap(FwSpacing.md),
          ],
          Flexible(
            child: SelectableText(
              revealed ? connection.dsn : masked,
              maxLines: 1,
              style: context.type.mono,
            ),
          ),
          if (secret)
            _SmallIconButton(
              revealed ? Icons.visibility_off : Icons.visibility,
              tooltip: revealed ? 'Mask' : 'Reveal',
              onTap: () => setState(() {
                revealed ? _revealed.remove(key) : _revealed.add(key);
              }),
            ),
          _SmallIconButton(
            Icons.copy,
            tooltip: 'Copy',
            onTap: () => Clipboard.setData(ClipboardData(text: connection.dsn)),
          ),
        ],
      ),
    );
  }

  Widget _configRow(
    BuildContext context,
    String key,
    MapEntry<String, Object?> entry,
  ) {
    var value = entry.value;
    var secret = isSecretLikeKey(entry.key);
    var revealed = _revealed.contains(key);
    if (secret && !revealed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Text('${entry.key}: ••••', style: context.type.mono),
            _SmallIconButton(
              Icons.visibility,
              tooltip: 'Reveal',
              onTap: () => setState(() => _revealed.add(key)),
            ),
          ],
        ),
      );
    }
    if (value is Map || value is List) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.key}:', style: context.type.mono),
            Padding(
              padding: const EdgeInsets.only(left: FwSpacing.xl),
              child: JsonView(
                data: value,
                showToolbar: false,
                searchable: false,
                maxHeight: 240,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Flexible(
            child: SelectableText(
              '${entry.key}: $value',
              maxLines: 1,
              style: context.type.mono,
            ),
          ),
          if (secret)
            _SmallIconButton(
              Icons.visibility_off,
              tooltip: 'Mask',
              onTap: () => setState(() => _revealed.remove(key)),
            ),
        ],
      ),
    );
  }
}

/// One published link: the label opens it, the resolved URL sits beside it.
/// A relative URL with no base to resolve against renders as plain text —
/// an honest "the server did not say where it listens".
class _LinkRow extends StatelessWidget {
  const _LinkRow(this.link, {required this.baseUrl});

  final ServerLink link;
  final String? baseUrl;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var resolved = resolveLinkUrl(link.url, baseUrl: baseUrl);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
      child: Row(
        children: [
          resolved == null
              ? Text(link.label, style: context.type.bodySmall)
              : _UrlLink(resolved, label: link.label),
          const Gap(FwSpacing.md),
          Flexible(
            child: Text(
              resolved ?? link.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.mono.copyWith(color: colors.mut2),
            ),
          ),
          if (link.description != null) ...[
            const Gap(FwSpacing.md),
            Flexible(
              child: Text(
                link.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.caption.copyWith(color: colors.mut2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A connection's kind — `postgres`, `redis` — as a colored tag. A word the
/// GUI does not need to understand, per [ServerConnection.kind].
class _KindChip extends StatelessWidget {
  const _KindChip(this.kind);

  final String kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: context.colors.accentSoft,
        borderRadius: BorderRadius.circular(context.radii.micro),
      ),
      child: Text(
        kind,
        style: context.type.micro.copyWith(color: context.colors.accent),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton(
    this.icon, {
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: FwSpacing.sm),
      child: Tooltip(
        message: tooltip,
        child: Tappable.builder(
          onTap: onTap,
          builder: (context, hovered) => Icon(
            icon,
            size: FwIconSize.sm,
            color: hovered ? context.colors.accent : context.colors.mut3,
          ),
        ),
      ),
    );
  }
}

class _NoInfoHint extends StatelessWidget {
  const _NoInfoHint();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This server has not published anything about itself.',
              style: context.type.bodySmall.copyWith(color: colors.mut),
            ),
            const Gap(FwSpacing.sm),
            Text(
              'It can, in one call after `serve` returns:',
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
            const Gap(FwSpacing.lg),
            _Slab(
              child: SelectableText(
                'FlutterwareServer.info(ServerInfo(\n'
                "  baseUrl: 'http://localhost:\$port',\n"
                "  environment: 'dev',\n"
                "  links: [ServerLink('Health', '/health')],\n"
                '));',
                style: context.type.mono.copyWith(color: colors.mut),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTimeline extends StatelessWidget {
  const _EventTimeline(this.events);

  final List<ServerEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const LoadingState(
        title: 'Attached — waiting for events',
        message: 'Anything this server reports will land here.',
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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: panelGutter,
        vertical: FwSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            _timestamp(event.time),
            style: context.type.mono.copyWith(color: context.colors.mut2),
          ),
          const Gap(FwSpacing.md),
          _ChannelChip(event),
          const Gap(FwSpacing.md),
          Expanded(
            child: Text(
              _summary(event),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.mono,
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

  /// Fixed width, so the summaries beside them line up down the stream: the
  /// channel is a column, and a column whose left edge moves per row is one the
  /// eye cannot run down.
  static const _width = 34.0;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var failed = _failed(event);
    var color = failed
        ? colors.red
        : switch (event.channel) {
            'http' => colors.accent,
            'sql' => colors.grn,
            'log' => colors.mut,
            _ => colors.info,
          };
    return Container(
      width: _width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(context.radii.micro),
      ),
      child: Text(
        event.channel,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: context.type.micro.copyWith(color: color),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.dns_outlined,
      title: 'No servers are announcing themselves',
      message:
          'Report from one with package:flutterware/server.dart — an event, '
          'a span or a handler is enough; it publishes on first use.',
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
