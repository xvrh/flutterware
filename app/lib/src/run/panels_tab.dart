import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterware/channels.dart';
import 'package:flutterware/channels_ui.dart';
import 'package:logging/logging.dart';

import '../ui/design/spacing.dart';
import '../ui/design/tokens.dart';
import 'channel_client.dart';
import 'connection.dart';
import 'database_panel_view.dart';
import 'flag_memory.dart';
import 'handle.dart';
import 'panel_client.dart';

final _logger = Logger('run_panels');

/// The app's own panels, in the cockpit — the Screen tab's counterpart for
/// everything the app chose to report about itself.
///
/// **The Screen of a run is what flutterware can see; this is what the app
/// says.** It attaches to the channels the run guest installed, lists whatever
/// devbar plugins declared themselves, and renders each from its descriptor
/// with the same widgets the in-app overlay uses.
class PanelsTab extends StatefulWidget {
  const PanelsTab({
    super.key,
    required this.handle,
    required this.memory,
    this.connect,
  });

  final RunHandle handle;

  /// The host's half of Decision 4: wishes to push, and the knobs this project
  /// has shown before.
  final FlagMemory memory;

  /// How to reach the app. Injected for the test that drives a fake VM.
  final Future<RunConnection> Function(String wsUri)? connect;

  @override
  State<PanelsTab> createState() => _PanelsTabState();
}

class _PanelsTabState extends State<PanelsTab> {
  RunChannelClient? _client;
  RunPanels? _panels;
  StreamSubscription<void>? _changes;
  StreamSubscription<void>? _feed;

  List<PanelDescriptor> _descriptors = const [];
  String? _selected;
  String? _error;
  var _loading = true;

  /// What each knob write is waiting on, so a slider does not fight the reply
  /// to the previous drag.
  var _writes = Future<void>.value();

  String get _projectKey => FlagMemory.keyFor(widget.handle);

  @override
  void initState() {
    super.initState();
    unawaited(_attach());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_feed?.cancel());
    unawaited(_client?.close());
    super.dispose();
  }

  /// One rebuild per drain rather than one per event: a pull returns a whole
  /// batch of frames, and a feed under load would otherwise cost a setState
  /// each.
  var _repainting = false;

  void _repaint() {
    if (_repainting || !mounted) return;
    _repainting = true;
    scheduleMicrotask(() {
      _repainting = false;
      if (mounted) setState(() {});
    });
  }

  /// The events this attachment is holding, bucketed by the feed that reported
  /// them. Oldest first, which is the order [PanelView] draws.
  Map<String, List<InspectorEvent>> _feedEvents(PanelDescriptor panel) {
    if (panel.feeds.isEmpty) return const {};
    var byChannel = {
      for (var feed in panel.feeds) panel.feedChannel(feed.id): feed.id,
    };
    var events = {for (var feed in panel.feeds) feed.id: <InspectorEvent>[]};
    for (var event in _client?.received ?? const <InspectorEvent>[]) {
      var feedId = byChannel[event.channel];
      if (feedId != null) events[feedId]!.add(event);
    }
    return events;
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
      // One peer id per cockpit pane: an MCP call attached to the same app gets
      // its own queue and its own replay rather than racing this one.
      // The nonce matters: a re-created pane racing its predecessor's async
      // detach must not share a peer id, or the detach tears down the new
      // attachment and every in-flight reply dies with it — found by the
      // database panel's schema read, 2026-08-12.
      var client = await RunChannelClient.attach(
        connection,
        peer: 'cockpit:${widget.handle.key}:${identityHashCode(this)}',
      );
      if (!mounted) {
        await client.close();
        return;
      }
      _client = client;
      _panels = RunPanels(client);
      _changes = _panels!.changed.listen((_) => unawaited(_list()));
      // Feed events need no subscription of their own — the attachment already
      // carries every channel, replay included, and holds them. This only has
      // to notice that the held list grew.
      _feed = client.events.listen((_) => _repaint());
      await _applyWishes();
      await _list();
    } on Object catch (e) {
      _logger.fine('could not attach to ${widget.handle.key}: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        // An app built before this existed simply has no channel extension —
        // a fact about the app, not a failure of the cockpit.
        _error = 'This app is not reporting any panels.';
      });
    }
  }

  /// Pushes what the host remembers before reading anything, so the first list
  /// already shows the values somebody asked for rather than flickering
  /// through the defaults.
  Future<void> _applyWishes() async {
    var wishes = widget.memory.wishes(_projectKey);
    if (wishes.isEmpty) return;
    for (var entry in wishes.entries) {
      try {
        await _panels!.invoke('flags', 'preset', {
          'name': entry.key,
          'value': entry.value,
        });
      } on Object catch (e) {
        // A panel that offers no `preset` is not an error — it is a plugin
        // that never claimed to take one.
        _logger.fine('preset ${entry.key} refused: $e');
      }
    }
  }

  Future<void> _list() async {
    try {
      var listed = await _panels!.list();
      if (!mounted) return;
      for (var panel in listed) {
        widget.memory.remember(_projectKey, panel.knobs);
      }
      setState(() {
        _descriptors = listed;
        _loading = false;
        _error = null;
      });
    } on Object catch (e) {
      _logger.fine('listing panels failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _setKnob(String panelId, String name, Object? value) {
    // Remembered before it is sent: a wish is what the human asked for, and it
    // has to outlive both the reply and the run.
    widget.memory.wish(_projectKey, name, value);
    _writes = _writes.then((_) async {
      try {
        await _panels!.setKnob(panelId, name, value);
      } on Object catch (e) {
        _logger.fine('setting $name failed: $e');
      }
      await _list();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.xl),
          child: Text(
            _error!,
            style: context.type.body.copyWith(color: context.colors.mut),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_descriptors.isEmpty) {
      return Center(
        child: Text(
          'This app declares no panels.',
          style: context.type.body.copyWith(color: context.colors.mut),
        ),
      );
    }

    var current = _descriptors
        .firstWhere(
          (panel) => panel.id == _selected,
          orElse: () => _descriptors.first,
        )
        .id;
    var panel = _descriptors.firstWhere((p) => p.id == current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only when there is a choice to make: one panel is the ordinary case,
        // and a chooser over a single entry is furniture.
        if (_descriptors.length > 1)
          _PanelStrip(
            panels: _descriptors,
            current: current,
            onSelect: (id) => setState(() => _selected = id),
          ),
        Expanded(
          // A database earns a bespoke browser; everything else renders from
          // its descriptor. The `db:` prefix is `DatabasePanelSource.panelId`.
          child: panel.id.startsWith('db:')
              ? DatabasePanelView(
                  key: ValueKey(panel.id),
                  panels: _panels!,
                  descriptor: panel,
                  events: _feedEvents(panel),
                  details: (eventId) => _client!.details(eventId),
                )
              : PanelView(
                  descriptor: panel,
                  events: _feedEvents(panel),
                  onKnob: (name, value) => _setKnob(panel.id, name, value),
                  onAction: (id, args) => unawaited(_run(panel.id, id, args)),
                  // An item action carries the id of the event it was pressed on and
                  // nothing else — see `Panel.emit`, which hands the app that same id
                  // so it can look up what the row was about.
                  onItemAction: (id, event) =>
                      unawaited(_run(panel.id, id, {'event': event})),
                  onReadState: (id) => unawaited(_read(panel.id, id)),
                  states: _states,
                  busy: _busy,
                  results: _results,
                ),
        ),
      ],
    );
  }

  final _states = <String, Map<String, Object?>>{};
  final _busy = <String>{};
  final _results = <String, String>{};

  Future<void> _run(
    String panelId,
    String actionId,
    Map<String, Object?> args,
  ) async {
    setState(() => _busy.add(actionId));
    try {
      var result = await _panels!.invoke(panelId, actionId, args);
      if (!mounted) return;
      setState(() => _results[actionId] = '$result');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _results[actionId] = '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(actionId));
    }
    await _list();
  }

  Future<void> _read(String panelId, String stateId) async {
    try {
      var snapshot = await _panels!.state(panelId, stateId);
      if (!mounted) return;
      setState(() => _states[stateId] = snapshot);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _states[stateId] = {'error': '$e'});
    }
  }
}

/// Which of the app's panels is showing — the dock strip's own idiom, so it
/// reads as the App tab's second level rather than as widgets from another
/// design system.
class _PanelStrip extends StatelessWidget {
  const _PanelStrip({
    required this.panels,
    required this.current,
    required this.onSelect,
  });

  final List<PanelDescriptor> panels;
  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.panel,
          border: Border(bottom: BorderSide(color: context.colors.line)),
        ),
        child: Row(
          children: [
            for (var panel in panels)
              InkWell(
                onTap: () => onSelect(panel.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: panel.id == current
                            ? context.colors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    panel.label,
                    style: context.type.caption.copyWith(
                      color: panel.id == current
                          ? context.colors.ink
                          : context.colors.mut,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
