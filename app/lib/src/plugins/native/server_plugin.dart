import 'package:flutter/material.dart';
import 'package:flutterware/server.dart';

import '../native_plugin.dart';
import 'server_core.dart';

export 'server_core.dart' show ServerCore, serverPluginId;

/// The GUI half of server inspection: the raw timeline the spike calls for.
///
/// Everything the plugin *knows* — which servers announce themselves, their
/// events, the shaped request list — is in [ServerCore], so `fw` and an agent
/// reach the same answers. This class exists because `buildPanel` returns a
/// `Widget`.
class ServerPlugin extends NativePlugin<ServerCore> {
  ServerPlugin(super.core);

  @override
  Widget buildPanel(BuildContext context) => _ServerPanel(this);
}

/// Owns the subscription: mounting is what starts tracking — attaching to
/// announced servers and watching the run dir for new ones.
class _ServerPanel extends StatefulWidget {
  const _ServerPanel(this.plugin);

  final ServerPlugin plugin;

  @override
  State<_ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<_ServerPanel> {
  /// `<server key>/<event id>` rows the user expanded.
  final _expanded = <String>{};

  ServerCore get _core => widget.plugin.core;

  @override
  void initState() {
    super.initState();
    _core.track();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var servers = _core.servers;
        if (servers.isEmpty) return const _EmptyHint();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ServerBar(servers),
            const Divider(height: 1),
            Expanded(child: _timeline(servers)),
          ],
        );
      },
    );
  }

  Widget _timeline(List<TrackedServer> servers) {
    var entries = [
      for (var server in servers)
        for (var event in server.events) (server: server, event: event),
    ]..sort((a, b) => b.event.time.compareTo(a.event.time));
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Attached — waiting for events.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        var entry = entries[index];
        var key =
            '${entry.server.handle.name}-${entry.server.handle.pid}'
            '/${entry.event.id}';
        return _EventRow(
          event: entry.event,
          serverName: servers.length > 1 ? entry.server.handle.name : null,
          expanded: _expanded.contains(key),
          related: _expanded.contains(key)
              ? _related(entry.server, entry.event)
              : const [],
          onTap: () => setState(() {
            _expanded.contains(key)
                ? _expanded.remove(key)
                : _expanded.add(key);
          }),
        );
      },
    );
  }

  /// What else happened under the same correlation id — the queries and log
  /// lines an expanded request caused.
  List<ServerEvent> _related(TrackedServer server, ServerEvent event) {
    if (event.rid == null) return const [];
    return [
      for (var other in server.events)
        if (other.rid == event.rid && other.id != event.id) other,
    ];
  }
}

class _ServerBar extends StatelessWidget {
  const _ServerBar(this.servers);

  final List<TrackedServer> servers;

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
            Chip(
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
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.expanded,
    required this.related,
    required this.onTap,
    this.serverName,
  });

  final ServerEvent event;
  final String? serverName;
  final bool expanded;
  final List<ServerEvent> related;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var time = event.time;
    var timestamp =
        '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}'
        '.${time.millisecond.toString().padLeft(3, '0')}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                if (serverName != null) ...[
                  const SizedBox(width: 8),
                  Text(serverName!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            if (expanded) _Details(event: event, related: related),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.event, required this.related});

  final ServerEvent event;
  final List<ServerEvent> related;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var mono = theme.textTheme.bodySmall!.copyWith(fontFamily: 'monospace');
    return Padding(
      padding: const EdgeInsets.only(left: 88, top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var entry in event.payload.entries)
            Text('${entry.key}: ${entry.value}', style: mono),
          if (related.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('caused:', style: theme.textTheme.bodySmall),
            for (var other in related)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  '[${other.channel}] ${_summary(other)}',
                  style: mono,
                ),
              ),
          ],
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
    var failed =
        event.payload['error'] != null ||
        switch (event.payload['status']) {
          int status => status >= 500,
          _ => false,
        };
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

String _summary(ServerEvent event) {
  var p = event.payload;
  String ms() {
    var value = p['ms'];
    return value is num ? ' (${value.toStringAsFixed(1)}ms)' : '';
  }

  return switch (event.channel) {
    'http' => '${p['method']} ${p['path']} → ${p['status']}${ms()}',
    'sql' => '${p['query']}${ms()}',
    'log' => '${p['level']}: ${p['message']}',
    _ => p.toString(),
  };
}

String _two(int n) => n.toString().padLeft(2, '0');
