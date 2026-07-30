import 'package:flutter/material.dart';
import 'package:flutterware/server.dart';

import '../../address/address_scope.dart';
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ServerBar(servers, shown: server),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 380,
                    child: _RequestList(
                      server: server,
                      requests: requests.reversed.toList(),
                      byRid: byRid,
                      selectedId: selected?.id,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selected == null
                        ? _EventTimeline(events)
                        : _RequestDetail(
                            server: server,
                            request: selected,
                            caused: byRid[selected.rid] ?? const [],
                          ),
                  ),
                ],
              ),
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
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (var server in servers)
            InputChip(
              selected: identical(server, shown),
              showCheckmark: false,
              avatar: Icon(
                Icons.circle,
                size: 10,
                color: server.stopped
                    ? theme.disabledColor
                    : server.connected
                    ? Colors.green.shade600
                    : Colors.orange.shade600,
              ),
              label: Text(
                server.stopped
                    ? '${server.handle.name} (stopped)'
                    : server.connected
                    ? '${server.handle.name} · pid ${server.handle.pid}'
                    : '${server.handle.name} · reconnecting',
                style: theme.textTheme.bodySmall,
              ),
              onPressed: () => AddressScope.write(
                context,
              ).setSegments(serverSegments(server.handle.name)),
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
  });

  final TrackedServer server;

  /// Newest first.
  final List<ServerEvent> requests;
  final Map<String, List<ServerEvent>> byRid;
  final int? selectedId;

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
  });

  final TrackedServer server;
  final ServerEvent request;
  final bool selected;

  /// The largest repeat count among this request's queries; 0 for none.
  final int repeatedCount;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var p = request.payload;
    var failed = _failed(request);
    return InkWell(
      onTap: () => AddressScope.write(
        context,
      ).setSegments(serverSegments(server.handle.name, requestId: request.id)),
      child: Container(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            _StatusDot(failed: failed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${p['method']} ${p['path']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
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
            Text(
              _ms(p['ms']),
              style: theme.textTheme.bodySmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.hintColor,
              ),
            ),
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

/// The selected request: headline, N+1 warnings, the waterfall, the logs.
class _RequestDetail extends StatelessWidget {
  const _RequestDetail({
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
    var p = request.payload;
    var repeated = repeatedQueries(caused);
    var spans = [
      for (var event in caused)
        if (event.payload['ms'] is num) event,
    ];
    var logs = [
      for (var event in caused)
        if (event.payload['ms'] is! num) event,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${p['method']} ${p['path']} → ${p['status']}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(_ms(p['ms']), style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Back to the timeline',
              onPressed: () => AddressScope.write(
                context,
              ).setSegments(serverSegments(server.handle.name)),
            ),
          ],
        ),
        if (p['error'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${p['error']}',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        for (var entry in repeated.entries)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'N+1: this query runs ${entry.value}× in this request\n'
              '${entry.key}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        _Waterfall(request: request, spans: spans),
        if (logs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Logs', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (var log in logs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                _summary(log),
                style: theme.textTheme.bodySmall!.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
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
  const _Waterfall({required this.request, required this.spans});

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
                style: theme.textTheme.bodySmall!.copyWith(
                  fontFamily: 'monospace',
                ),
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
          row(
            _summary(span),
            ((span.time.millisecondsSinceEpoch - (span.payload['ms']! as num)) -
                    start)
                .toDouble(),
            (span.payload['ms']! as num).toDouble(),
            span.channel == 'sql'
                ? Colors.teal.shade400
                : Colors.purple.shade300,
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
    var time = event.time;
    var timestamp =
        '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}'
        '.${time.millisecond.toString().padLeft(3, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text(
            timestamp,
            style: theme.textTheme.bodySmall!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: theme.hintColor,
            ),
          ),
          const SizedBox(width: 8),
          _ChannelChip(event),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _summary(event),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
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

String _two(int n) => n.toString().padLeft(2, '0');

extension<T> on Iterable<T> {
  T? get firstOrNull {
    var it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
