import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';

import '../ui/json_view.dart';
import '../ui/tappable.dart';
import 'connection.dart';
import 'handle.dart';
import 'network_tracker.dart';
import '../ui/design/design.dart';
import '../ui/loading_state.dart';
import '../ui/error_state.dart';
import '../ui/empty_state.dart';

final _logger = Logger('run_network');

/// The run's HTTP traffic — a native tab, present for every debug run.
///
/// The data is the VM's own http profile, the source behind DevTools' Network
/// page, so this works against any app the cockpit can reach: no devbar, no
/// opt-in, no wrapper client. What the app *chose* to say lives in the App
/// tab; this is what flutterware can see.
///
/// The look follows the server panel's Requests tab deliberately — the two
/// are the same thing seen from opposite ends of the wire, and a person moves
/// between them on one bug.
class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key, required this.handle, this.connect});

  final RunHandle handle;

  /// How to reach the app. Injected for tests that drive a fake VM.
  final Future<RunConnection> Function(String wsUri)? connect;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  RunConnection? _connection;
  RunNetworkTracker? _tracker;
  StreamSubscription<void>? _changes;
  String? _error;
  var _loading = true;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _tracker?.dispose();
    unawaited(_connection?.close());
    super.dispose();
  }

  Future<void> _attach() async {
    var wsUri = widget.handle.vmService;
    if (wsUri == null) {
      setState(() {
        _loading = false;
        _error = 'This run has no VM service to attach to.';
      });
      return;
    }
    try {
      var connection = await (widget.connect ?? RunConnection.connect)(wsUri);
      if (!mounted) {
        unawaited(connection.close());
        return;
      }
      _connection = connection;
      var tracker = RunNetworkTracker(connection);
      _tracker = tracker;
      _changes = tracker.changes.listen((_) {
        if (mounted) setState(() {});
      });
      await tracker.poll();
      tracker.start();
      if (mounted) setState(() => _loading = false);
    } on Object catch (e) {
      _logger.fine('could not attach to ${widget.handle.key}: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not reach this app.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var tracker = _tracker;
    if (_loading) return const LoadingState(title: 'Reading the network log…');
    if (_error != null || tracker == null) {
      return ErrorState(title: 'Could not reach this app', message: _error);
    }
    if (tracker.broken) {
      return const ErrorState(title: 'This app stopped answering');
    }
    var requests = tracker.requests
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    var newestFirst = requests.reversed.toList();
    var selected = requests.where((r) => r.id == _selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: requests.isEmpty
              ? const EmptyState(
                  icon: Icons.swap_vert,
                  title: 'No requests yet',
                  message: 'Anything the app fetches lands here.',
                )
              : selected == null
              ? _RequestList(
                  requests: newestFirst,
                  selectedId: null,
                  showTime: true,
                  onSelect: _select,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    var detail = _RequestDetail(
                      // A new state per request *and* per completion: the
                      // same id goes from in-flight to answered, and the
                      // detail refetches when it does.
                      key: ValueKey(
                        '${selected.id}:${selected.response?.statusCode}',
                      ),
                      tracker: tracker,
                      request: selected,
                      onClose: () => _select(null),
                    );
                    // Below this there is no room for two columns beside the
                    // 380px list — the detail takes the pane and close is the
                    // way back.
                    if (constraints.maxWidth < 640) return detail;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 380,
                          child: _RequestList(
                            requests: newestFirst,
                            selectedId: selected.id,
                            onSelect: _select,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Text(
                '${requests.length} '
                'request${requests.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: requests.isEmpty
                    ? null
                    : () {
                        _select(null);
                        unawaited(tracker.clear());
                      },
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _select(String? id) => setState(() => _selectedId = id);
}

class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.requests,
    required this.selectedId,
    required this.onSelect,
    this.showTime = false,
  });

  /// Newest first.
  final List<HttpProfileRequestRef> requests;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  /// True in the full-width form, where there is room for a timestamp.
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: requests.length,
      itemBuilder: (context, index) => _RequestRow(
        request: requests[index],
        selected: requests[index].id == selectedId,
        showTime: showTime,
        onSelect: onSelect,
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.selected,
    required this.onSelect,
    this.showTime = false,
  });

  final HttpProfileRequestRef request;
  final bool selected;
  final ValueChanged<String?> onSelect;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var status = networkStatusOf(request);
    return Tappable.builder(
      onTap: () => onSelect(request.id),
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
                _timestamp(request.startTime),
                style: _mono(context, color: theme.hintColor),
              ),
              const SizedBox(width: 10),
            ],
            _StatusDot(status: status),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${request.method} ${_pathOf(request.uri)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(context, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status is int
                  ? '$status'
                  : status is String
                  ? status
                  : '…',
              style: _mono(
                context,
                color: status is int && status >= 400
                    ? theme.colorScheme.error
                    : theme.hintColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _ms(networkDurationOf(request)),
              style: _mono(context, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  /// An int code, `ERR`, or null while in flight.
  final Object? status;

  @override
  Widget build(BuildContext context) => Icon(
    Icons.circle,
    size: 8,
    color: status == null
        ? Theme.of(context).hintColor
        : status is int && (status! as int) < 400
        ? Colors.green.shade600
        : Colors.red.shade600,
  );
}

/// The selected request, in tabs: the request and response messages, and the
/// profiler's own timing events.
class _RequestDetail extends StatefulWidget {
  const _RequestDetail({
    super.key,
    required this.tracker,
    required this.request,
    required this.onClose,
  });

  final RunNetworkTracker tracker;
  final HttpProfileRequestRef request;
  final VoidCallback onClose;

  @override
  State<_RequestDetail> createState() => _RequestDetailState();
}

class _RequestDetailState extends State<_RequestDetail> {
  static const _tabs = ['request', 'response', 'timing'];
  var _tab = 'response';

  late final Future<HttpProfileRequest?> _detail = widget.tracker.detailsFor(
    widget.request.id,
  );

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var request = widget.request;
    var status = networkStatusOf(request);
    var error = networkErrorOf(request);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${request.method} ${_pathOf(request.uri)}'
                  '${status == null ? '' : ' → $status'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(context, fontSize: 15),
                ),
              ),
              Text(
                _ms(networkDurationOf(request)),
                style: _mono(context, fontSize: 15),
              ),
              const SizedBox(width: 8),
              _CopyAsCurlButton(detail: _detail),
              IconButton(
                icon: const Icon(Icons.close, size: FwIconSize.lg),
                tooltip: 'Back to the request list',
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              error,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Wrap(
            spacing: 4,
            children: [
              for (var name in _tabs)
                TextButton(
                  style: name == _tab
                      ? TextButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                        )
                      : null,
                  onPressed: () => setState(() => _tab = name),
                  child: Text(name),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder(
            future: _detail,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState(title: 'Reading the request…');
              }
              var detail = snapshot.data;
              if (detail == null) {
                return const EmptyState(
                  icon: Icons.history_toggle_off,
                  title: 'No longer available',
                  message: 'The app restarted, and this request went with it.',
                );
              }
              return switch (_tab) {
                'request' => _HttpMessageTab(detail: detail, response: false),
                'timing' => _TimingTab(detail: detail),
                _ => _HttpMessageTab(detail: detail, response: true),
              };
            },
          ),
        ),
      ],
    );
  }
}

/// One side of the HTTP exchange: headers and body, from the profile's lazy
/// detail. The body arrives as bytes — decoded here, folded when it is JSON.
class _HttpMessageTab extends StatelessWidget {
  const _HttpMessageTab({required this.detail, required this.response});

  final HttpProfileRequest detail;

  /// False for the request side, true for the response side.
  final bool response;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var mono = _mono(context);
    var headers = _headersOf(detail, response: response);
    var body = response ? detail.responseBody : detail.requestBody;
    if (headers == null && (body == null || body.isEmpty)) {
      return Center(
        child: Text(
          response && detail.response == null
              ? 'No response yet.'
              : 'Not captured.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    String? bodyText;
    var binary = false;
    if (body != null && body.isNotEmpty) {
      try {
        bodyText = utf8.decode(body);
      } on FormatException {
        binary = true;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Headers', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (var entry in (headers ?? const {}).entries)
          for (var value
              in entry.value is List ? entry.value! as List : [entry.value])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: SelectableText('${entry.key}: $value', style: mono),
            ),
        const SizedBox(height: 16),
        Text('Body', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (bodyText == null)
          Text(
            binary ? '${body!.length} bytes of binary data.' : 'Empty.',
            style: theme.textTheme.bodySmall,
          )
        // A JSON body folds; anything else stays plain text. Sniffing the
        // first character beats trusting content-type, which lies.
        else if (bodyText.trimLeft().startsWith(RegExp(r'[\[{]')))
          JsonView.source(bodyText, maxHeight: 520)
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
            ),
            child: SelectableText(bodyText, style: mono),
          ),
      ],
    );
  }
}

/// The profiler's own event list — connection, request sent, first byte,
/// download — with the gap to the previous event, which is where the time
/// went.
class _TimingTab extends StatelessWidget {
  const _TimingTab({required this.detail});

  final HttpProfileRequest detail;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var events = detail.events;
    if (events.isEmpty) {
      return const EmptyState(icon: Icons.timeline, title: 'No timing events');
    }
    var previous = detail.startTime;
    var rows = <(String, Duration)>[];
    for (var event in events) {
      rows.add((event.event, event.timestamp.difference(previous)));
      previous = event.timestamp;
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var (label, gap) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(child: Text(label, style: _mono(context))),
                Text(
                  '+${_ms(gap.inMicroseconds / 1000)}',
                  style: _mono(context, color: theme.hintColor),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One click from "I see the request" to "I can reproduce it in a terminal".
/// Unlike the server panel's version this needs no published base URL — the
/// profile records the absolute URI the client actually called.
class _CopyAsCurlButton extends StatelessWidget {
  const _CopyAsCurlButton({required this.detail});

  final Future<HttpProfileRequest?> detail;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.terminal, size: FwIconSize.lg),
      tooltip: 'Copy as curl',
      onPressed: () async {
        var resolved = await detail;
        if (resolved == null) return;
        await Clipboard.setData(ClipboardData(text: curlForRequest(resolved)));
      },
    );
  }
}

/// The request replayed from a shell — same shape as the server panel's
/// `curlCommand`, built from the profile's detail instead of a feed event.
String curlForRequest(HttpProfileRequest detail) {
  var methodFlag = detail.method == 'GET' ? '' : ' -X ${detail.method}';
  var lines = ['curl$methodFlag ${_shellQuote(detail.uri.toString())}'];
  var headers = _headersOf(detail, response: false);
  if (headers != null) {
    for (var entry in headers.entries) {
      var name = entry.key.toLowerCase();
      if (name == 'host' || name == 'content-length') continue;
      var values = entry.value is List ? entry.value! as List : [entry.value];
      for (var value in values) {
        lines.add('-H ${_shellQuote('${entry.key}: $value')}');
      }
    }
  }
  var body = detail.requestBody;
  if (body != null && body.isNotEmpty) {
    try {
      lines.add('--data-raw ${_shellQuote(utf8.decode(body))}');
    } on FormatException {
      // A binary body has no faithful shell form; the command without it
      // still names the call.
    }
  }
  return lines.join(' \\\n  ');
}

String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Headers for one side, null when that side errored or was never recorded —
/// the typed model throws on access after an error.
Map<String, Object?>? _headersOf(
  HttpProfileRequest detail, {
  required bool response,
}) {
  var raw = response
      ? detail.response?.headers
      : (detail.request?.hasError ?? true)
      ? null
      : detail.request?.headers;
  return raw?.cast<String, Object?>();
}

String _pathOf(Uri uri) {
  var path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}

String _ms(Object? value) =>
    value is num ? '${value.toStringAsFixed(1)}ms' : '';

/// The server panel's mono style, copied on purpose — the two request lists
/// should read as siblings.
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
