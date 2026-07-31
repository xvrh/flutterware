import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

import '../../address/address_scope.dart';
import '../../run/entrypoints.dart';
import '../../run/handle.dart';
import '../../run/inventory.dart';
import '../../run/launch.dart';
import '../../run/logs.dart';
import '../../ui/design/design.dart';
import '../../ui/empty_state.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../../utils/daemon/device.dart';
import '../native_plugin.dart';
import 'run_address.dart';
import 'run_core.dart';

export 'run_core.dart' show RunCore, runPluginId;

/// The GUI half of the run cockpit: a panel, and nothing else.
///
/// What is connected, what is busy, who holds it and what launching does all
/// live in [RunCore], so `fw` and an agent get the same answers from the same
/// code. This class exists because `buildPanel` returns a `Widget`.
class RunPlugin extends NativePlugin<RunCore> {
  RunPlugin(super.core);

  /// Starting a `flutter daemon` takes seconds and a cold build takes minutes,
  /// and the panel is worth photographing for neither. Without this a window
  /// capture catches the empty state and reports it as the device list.
  @override
  String? get busyWith {
    if (!core.isLive && core.devices.isEmpty) return 'finding devices';
    if (core.isStarting) return 'building';
    return null;
  }

  @override
  Widget buildPanel(BuildContext context) => _RunPanel(this);
}

/// **Runs are the subjects, not devices.**
///
/// The panel was a list of devices with a run squeezed into each row. That
/// fitted the first slice, strained in the second, and had nowhere to put the
/// third: a screenshot, a widget tree and a log stream do not go in a table
/// row. So it follows the server panel instead — subject chips, a tab strip,
/// and a pane — which is this problem already solved once in this codebase.
///
/// Starting a run is its own page rather than a button per entry point: four to
/// ten entry points as a row of buttons is a wall, and the knobs have nowhere
/// to go. See `docs/superpowers/specs/2026-07-31-run-cockpit-panel-design.md`.
class _RunPanel extends StatefulWidget {
  const _RunPanel(this.plugin);

  final RunPlugin plugin;

  @override
  State<_RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends State<_RunPanel> {
  RunCore get _core => widget.plugin.core;

  @override
  void initState() {
    super.initState();
    _core.track();
  }

  RunPlace _resolve(BuildContext context) => runPlace(
    [for (var i = 0; i < 2; i++) AddressScope.segment(context, i) ?? '']
      ..removeWhere((s) => s.isEmpty),
  );

  /// The run the place names, or the first one.
  ///
  /// By key rather than by identity, because the handle object is replaced on
  /// every probe — and by *falling back* rather than by showing nothing,
  /// because an address to a run that has since stopped should land you in the
  /// cockpit rather than in an error.
  RunHandle? _select(List<RunHandle> handles, RunPlace place) {
    if (place.runKey case var key?) {
      for (var handle in handles) {
        if (handle.key == key) return handle;
      }
    }
    return handles.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var handles = _core.handles;
        var failures = _core.failures;
        var place = _resolve(context);
        // A failure is looked up before a handle is fallen back to, so the
        // address you were already watching turns into the reason it died
        // rather than bouncing you to the form with nothing said.
        var failed = place.isNew || place.runKey == null
            ? null
            : _core.failureFor(place.runKey!);
        var shown = place.isNew || failed != null
            ? null
            : _select(handles, place);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SubjectBar(
              handles: handles,
              failures: failures,
              shown: shown,
              shownFailure: failed,
              isNew: place.isNew,
            ),
            const Divider(height: 1),
            Expanded(
              child: switch ((failed, shown)) {
                (var failure?, _) => _FailedRunPage(
                  failure: failure,
                  onDismiss: () {
                    _core.dismissFailure(failure.key);
                    if (mounted) {
                      AddressScope.write(
                        context,
                      ).setSegments(const [newRunSegment]);
                    }
                  },
                ),
                (_, var handle?) => _RunView(
                  core: _core,
                  handle: handle,
                  view: place.view,
                  onControl: _control,
                ),
                _ => _NewRunPage(core: _core, onLaunched: _goTo),
              },
            ),
          ],
        );
      },
    );
  }

  void _goTo(RunHandle handle) {
    if (!mounted) return;
    AddressScope.write(context).setSegments(runSegments(handle.key));
  }

  Future<void> _control(String action, RunHandle handle) async {
    try {
      await _core.control(action, handle);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

/// One chip per run, and New run on the right.
///
/// Every worktree's runs, not just this one's — a device held by another
/// checkout is exactly the case the cockpit exists to make visible. A foreign
/// run is chipped with its worktree's name so the list never implies you own
/// something you do not.
class _SubjectBar extends StatelessWidget {
  const _SubjectBar({
    required this.handles,
    required this.failures,
    required this.shown,
    required this.shownFailure,
    required this.isNew,
  });

  final List<RunHandle> handles;

  /// Runs that died before they started. Chipped alongside the live ones
  /// because a launch that failed is still something you asked for, and the
  /// bar going empty was the whole of what "it closed without explanation"
  /// looked like from here.
  final List<RunFailure> failures;

  final RunHandle? shown;
  final RunFailure? shownFailure;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FwSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: FwSpacing.sm,
              runSpacing: FwSpacing.xs,
              children: [
                for (var handle in handles)
                  _Pill(
                    label: '${handle.runLabel} · ${handle.deviceLabel}',
                    selected: !isNew && handle.key == shown?.key,
                    dot: true,
                    onTap: () => AddressScope.write(
                      context,
                    ).setSegments(runSegments(handle.key)),
                  ),
                for (var failure in failures)
                  _Pill(
                    label: '${failure.runLabel} · ${failure.deviceLabel}',
                    selected: !isNew && failure.key == shownFailure?.key,
                    dot: true,
                    dotColor: context.colors.red,
                    onTap: () => AddressScope.write(
                      context,
                    ).setSegments(runSegments(failure.key)),
                  ),
              ],
            ),
          ),
          const Gap(FwSpacing.sm),
          _Pill(
            label: '+ New run',
            // Selected when it is what is showing, which includes the case
            // where nothing is running and there was nothing else to show.
            selected:
                isNew ||
                (handles.isEmpty && shown == null && shownFailure == null),
            onTap: () =>
                AddressScope.write(context).setSegments(const [newRunSegment]),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot = false,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final bool dot;

  /// Green when absent — a live run. Red says the run is a failed one whose
  /// chip is being kept so its reason has somewhere to live.
  final Color? dotColor;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            if (dot) ...[
              Icon(Icons.circle, size: 8, color: dotColor ?? colors.grn),
              const SizedBox(width: 6),
            ],
            Text(label, style: context.type.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// One run: its header, its tabs, and whichever pane is open.
class _RunView extends StatelessWidget {
  const _RunView({
    required this.core,
    required this.handle,
    required this.view,
    required this.onControl,
  });

  final RunCore core;
  final RunHandle handle;
  final RunViewKind view;
  final void Function(String action, RunHandle handle) onControl;

  @override
  Widget build(BuildContext context) {
    var probe = core.probeOf(handle);
    var log = core.logOf(handle);
    var mine = handle.worktreeName == core.host.worktree.name;
    var state = _RunState.of(
      probe: probe,
      log: log,
      mine: mine,
      handle: handle,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RunHeader(
          handle: handle,
          state: state,
          mine: mine,
          onControl: onControl,
        ),
        _ViewTabs(runKey: handle.key, view: view, enabled: state.canInspect),
        const Divider(height: 1),
        Expanded(
          child: !state.canInspect
              ? _NotYet(state: state, handle: handle)
              : switch (view) {
                  RunViewKind.screen => _ScreenTab(core: core, handle: handle),
                  RunViewKind.tree => _TreeTab(core: core, handle: handle),
                  RunViewKind.logs => _LogsTab(core: core, handle: handle),
                },
        ),
      ],
    );
  }
}

/// **Capability, not liveness.**
///
/// The S-L1 finding, made visible. Hot reload is registered by the `flutter
/// run` and dies with it; the tree and the screenshots belong to the app and
/// outlive it. A header saying only "running" would hide exactly the difference
/// the buttons beside it are about to demonstrate.
class _RunState {
  const _RunState({
    required this.label,
    required this.canInspect,
    required this.canReload,
    required this.tone,
  });

  factory _RunState.of({
    required RunProbe? probe,
    required LaunchLog? log,
    required bool mine,
    required RunHandle handle,
  }) {
    if (probe == null) {
      return _RunState(
        label: log?.summary ?? 'not probed yet',
        canInspect: false,
        canReload: false,
        tone: _Tone.quiet,
      );
    }
    if (!probe.canInspect) {
      return _RunState(
        label: log?.progress ?? log?.summary ?? 'building',
        canInspect: false,
        canReload: false,
        tone: _Tone.quiet,
      );
    }
    if (!probe.launcher) {
      return const _RunState(
        // Not "stopped": the app is up and fully inspectable. What is gone is
        // the process that could have reloaded it.
        label: 'no launcher — cannot reload',
        canInspect: true,
        canReload: false,
        tone: _Tone.warn,
      );
    }
    if (!mine) {
      return _RunState(
        label: 'held by ${handle.worktreeName}',
        canInspect: true,
        canReload: false,
        tone: _Tone.quiet,
      );
    }
    return const _RunState(
      label: 'reloadable',
      canInspect: true,
      canReload: true,
      tone: _Tone.good,
    );
  }

  final String label;
  final bool canInspect;
  final bool canReload;
  final _Tone tone;
}

enum _Tone { good, warn, quiet }

class _RunHeader extends StatelessWidget {
  const _RunHeader({
    required this.handle,
    required this.state,
    required this.mine,
    required this.onControl,
  });

  final RunHandle handle;
  final _RunState state;
  final bool mine;
  final void Function(String action, RunHandle handle) onControl;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        FwSpacing.md,
        FwSpacing.lg,
        FwSpacing.sm,
      ),
      child: Row(
        children: [
          Flexible(
            flex: 0,
            child: Text(
              handle.runLabel,
              style: context.type.bodyStrong,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Gap(FwSpacing.sm),
          Text('on ${handle.deviceLabel}', style: context.type.bodyMuted),
          const Gap(FwSpacing.sm),
          if (!mine) ...[_Tag(handle.worktreeName), const Gap(FwSpacing.sm)],
          Flexible(
            flex: 0,
            child: Text(
              state.label,
              overflow: TextOverflow.ellipsis,
              style: context.type.caption.copyWith(
                color: switch (state.tone) {
                  _Tone.good => colors.grn,
                  _Tone.warn => colors.amber,
                  _Tone.quiet => colors.mut2,
                },
              ),
            ),
          ),
          const Spacer(),
          // Another worktree's run is shown read-only: it is useful to see, and
          // a tool that knew and would not say would be worse. Driving it is
          // its owner's business.
          if (mine) ...[
            _Action(
              'Reload',
              Icons.bolt_outlined,
              enabled: state.canReload,
              onPressed: () => onControl('reload', handle),
            ),
            _Action(
              'Restart',
              Icons.refresh_rounded,
              enabled: state.canReload,
              onPressed: () => onControl('restart', handle),
            ),
            _Action(
              'Stop',
              Icons.stop_rounded,
              enabled: true,
              onPressed: () => onControl('stop', handle),
            ),
          ],
        ],
      ),
    );
  }
}

/// Screen | Tree | Logs, written into the address.
///
/// **The strip is the extension point.** `Network` and `Data` are devbar
/// plugins reporting into the cockpit later, so it has to accept tabs this
/// build does not know about — which is why the address carries a tab *name*
/// and reading an unknown one falls back to the screen.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.runKey,
    required this.view,
    required this.enabled,
  });

  final String runKey;
  final RunViewKind view;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: FwSpacing.md, right: FwSpacing.md),
      child: Row(
        children: [
          for (var kind in RunViewKind.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                style: kind == view
                    ? TextButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                      )
                    : null,
                onPressed: enabled
                    ? () => AddressScope.write(
                        context,
                      ).setSegments(runSegments(runKey, view: kind))
                    : null,
                child: Text(switch (kind) {
                  RunViewKind.screen => 'Screen',
                  RunViewKind.tree => 'Tree',
                  RunViewKind.logs => 'Logs',
                }),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown while a run has no app to ask — a build in flight, or one that failed.
///
/// The logs are offered rather than described, because this is the state where
/// they are the only thing that can say what is happening.
class _NotYet extends StatelessWidget {
  const _NotYet({required this.state, required this.handle});

  final _RunState state;
  final RunHandle handle;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FwSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.mut2,
            ),
          ),
          const Gap(FwSpacing.md),
          Text(state.label, style: context.type.body),
          const Gap(FwSpacing.xs),
          Text(
            'Nothing can be read from an app that has not started. '
            'A cold build is minutes, not seconds.',
            textAlign: TextAlign.center,
            style: context.type.caption.copyWith(color: context.colors.mut2),
          ),
          if (handle.logPath case var path?) ...[
            const Gap(FwSpacing.sm),
            SelectableText(path, style: context.type.micro),
          ],
        ],
      ),
    ),
  );
}

/// A picture of the app, on demand.
///
/// **Not a live mirror, and it says so.** Each capture is a render and a PNG —
/// 66ms on this Mac, 42 on a simulator — so polling one would be a cost paid
/// continuously for a screen nobody is watching most of the time. The button is
/// the honest version until somebody wants a mirror enough to pay for it.
class _ScreenTab extends StatefulWidget {
  const _ScreenTab({required this.core, required this.handle});

  final RunCore core;
  final RunHandle handle;

  @override
  State<_ScreenTab> createState() => _ScreenTabState();
}

class _ScreenTabState extends State<_ScreenTab> {
  Uint8List? _image;
  String? _error;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _capture();
  }

  @override
  void didUpdateWidget(_ScreenTab old) {
    super.didUpdateWidget(old);
    // A different run in the same tab is a different subject, not a stale
    // picture of this one.
    if (old.handle.key != widget.handle.key) {
      _image = null;
      _error = null;
      _capture();
    }
  }

  Future<void> _capture() async {
    setState(() => _loading = true);
    try {
      var bytes = await widget.core.screenshot(widget.handle);
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabBar(
          loading: _loading,
          onRefresh: _capture,
          note: 'rendered by the app, so platform views will not appear',
        ),
        Expanded(
          child: _error != null
              ? _Failed(_error!)
              : _image == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(FwSpacing.lg),
                  child: Center(
                    child: Image.memory(
                      _image!,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// The widget tree, indented, with the file and line each widget came from.
///
/// The source is the point. It is what makes the tree actionable rather than
/// decorative, and it is the field the guest runtime could never read —
/// `_HasCreationLocation` is private to `package:flutter` — but the service
/// extension hands out freely.
class _TreeTab extends StatefulWidget {
  const _TreeTab({required this.core, required this.handle});

  final RunCore core;
  final RunHandle handle;

  @override
  State<_TreeTab> createState() => _TreeTabState();
}

class _TreeTabState extends State<_TreeTab> {
  InspectTree? _tree;
  String? _error;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_TreeTab old) {
    super.didUpdateWidget(old);
    if (old.handle.key != widget.handle.key) {
      _tree = null;
      _error = null;
      _read();
    }
  }

  Future<void> _read() async {
    setState(() => _loading = true);
    try {
      var tree = await widget.core.inspectTree(widget.handle);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var tree = _tree;
    var nodes = tree == null
        ? const <(InspectNode, int)>[]
        : _flatten(tree.root, 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabBar(
          loading: _loading,
          onRefresh: _read,
          note: tree == null ? null : '${nodes.length} widgets from your code',
        ),
        Expanded(
          child: _error != null
              ? _Failed(_error!)
              : tree != null && tree.root == null
              ? const _Hint('The app has not built a frame yet.')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.lg,
                    vertical: FwSpacing.sm,
                  ),
                  itemCount: nodes.length,
                  itemBuilder: (context, i) => _TreeRow(
                    node: nodes[i].$1,
                    depth: nodes[i].$2,
                    worktree: widget.core.host.worktree.path,
                  ),
                ),
        ),
      ],
    );
  }

  static Iterable<(InspectNode, int)> _flatten(
    InspectNode? node,
    int depth,
  ) sync* {
    if (node == null) return;
    yield (node, depth);
    for (var child in node.children) {
      yield* _flatten(child, depth + 1);
    }
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.worktree,
  });

  final InspectNode node;
  final int depth;
  final String worktree;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, top: 1, bottom: 1),
      child: Row(
        children: [
          Flexible(
            flex: 0,
            child: Text(
              node.description ?? node.type,
              style: context.type.bodySmall.copyWith(
                // The framework's own widgets are context, yours are the
                // subject. `createdByLocalProject` is the framework's verdict,
                // not a guess from the path.
                color: node.createdByLocalProject ? colors.ink : colors.mut2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (node.source case var source?) ...[
            const Gap(FwSpacing.sm),
            Flexible(
              child: Text(
                _sourceLabel(source, worktree),
                style: context.type.micro.copyWith(color: colors.mut3),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the launcher wrote, with the app's own output separable from the
/// build's.
///
/// Read from the file rather than from a stream, which is why it works before
/// the app exists and after it has gone.
class _LogsTab extends StatefulWidget {
  const _LogsTab({required this.core, required this.handle});

  final RunCore core;
  final RunHandle handle;

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  RunLogSource? _only;

  @override
  Widget build(BuildContext context) {
    var lines = widget.core.readLogs(widget.handle, only: _only, tail: 2000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.lg,
            vertical: FwSpacing.xs,
          ),
          child: Row(
            children: [
              for (var (label, value) in [
                ('All', null),
                ('App', RunLogSource.app),
                ('Build', RunLogSource.tool),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: FwSpacing.xs),
                  child: _Pill(
                    label: label,
                    selected: _only == value,
                    onTap: () => setState(() => _only = value),
                  ),
                ),
              const Spacer(),
              Text(
                '${lines.length} lines',
                style: context.type.micro.copyWith(color: context.colors.mut3),
              ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? _Hint(
                  _only == RunLogSource.app
                      ? 'The app has printed nothing. The build output is '
                            'under Build.'
                      : 'Nothing logged yet.',
                )
              // `reverse` rather than a scroll controller: it pins the view to
              // the newest line, which is the one anybody opening a log is
              // looking for, and keeps it pinned as more arrive. The list is
              // indexed from the end to match, so it still reads top-to-bottom
              // oldest-to-newest.
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.lg,
                    vertical: FwSpacing.sm,
                  ),
                  itemCount: lines.length,
                  itemBuilder: (context, i) =>
                      _LogRow(lines[lines.length - 1 - i]),
                ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.line);

  final RunLogLine line;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        line.text,
        style: _mono(
          context,
          color: line.error
              ? colors.red
              : line.source == RunLogSource.app
              ? colors.ink
              : colors.mut2,
        ),
      ),
    );
  }
}

/// Pick a device, pick an entry point, fill its knobs, start.
///
/// One column, in that order, and it opens filled in with whatever ran last —
/// so running the same thing again is opening the page and pressing Start.
/// An earlier draft had a two-column workspace with a recents row; it was
/// harder to follow than the four steps it was decorating.
class _NewRunPage extends StatefulWidget {
  const _NewRunPage({required this.core, required this.onLaunched});

  final RunCore core;
  final void Function(RunHandle) onLaunched;

  @override
  State<_NewRunPage> createState() => _NewRunPageState();
}

class _NewRunPageState extends State<_NewRunPage> {
  String? _device;
  ({String package, EntrypointRef entry})? _entry;
  final _knobs = <String, TextEditingController>{};
  final _flavor = TextEditingController();
  var _launching = false;
  String? _error;

  RunCore get _core => widget.core;

  List<({String package, EntrypointRef entry})> get _entries => [
    for (var package in _core.packages)
      for (var entry in _core.entrypointsFor(package))
        (package: package, entry: entry),
  ];

  @override
  void dispose() {
    for (var field in _knobs.values) {
      field.dispose();
    }
    _flavor.dispose();
    super.dispose();
  }

  /// Fills the form from the last launch, and from the first plausible choice
  /// when there has not been one.
  void _prime() {
    var entries = _entries;
    if (entries.isEmpty) return;
    var last = _core.lastLaunch;
    _device ??=
        last?.device ??
        _core.devices
            .where((d) => d.isConnected)
            .map((d) => d.id)
            .firstOrNull ??
        _core.devices.firstOrNull?.id;
    if (_entry == null) {
      _entry =
          entries
              .where(
                (e) =>
                    e.package == last?.package &&
                    e.entry.path == last?.entrypoint,
              )
              .firstOrNull ??
          entries.first;
      _rebuildKnobs(last?.knobs ?? const {});
      // The entry point's declaration is the default; what was actually run
      // last time wins over it, because overriding a flavor once usually means
      // overriding it again.
      _flavor.text = last?.flavor ?? _entry?.entry.flavor ?? '';
    }
  }

  void _rebuildKnobs(Map<String, String> values) {
    for (var field in _knobs.values) {
      field.dispose();
    }
    _knobs.clear();
    for (var knob in _entry?.entry.knobs ?? const <LaunchKnob>[]) {
      _knobs[knob.define] = TextEditingController(
        text: values[knob.define] ?? knob.defaultValue ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _prime();
    var entries = _entries;
    if (entries.isEmpty) {
      return const EmptyState(
        icon: Icons.play_circle_outline,
        title: 'No entry points',
        message:
            'Declare them in tool/flutterware.dart, or put a main() in '
            'the package’s lib/.',
      );
    }
    var device = _core.devices.where((d) => d.id == _device).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(FwSpacing.xl),
      children: [
        Text('New run', style: context.type.heading),
        const Gap(FwSpacing.lg),
        _Field(
          label: 'Device',
          child: _DevicePicker(
            devices: _core.devices,
            selected: _device,
            onChanged: (id) => setState(() => _device = id),
          ),
        ),
        const Gap(FwSpacing.lg),
        _Field(
          label: 'Entry point',
          child: _EntrypointPicker(
            entries: entries,
            selected: _entry,
            onChanged: (choice) => setState(() {
              _entry = choice;
              _rebuildKnobs(const {});
              _flavor.text = choice.entry.flavor ?? '';
            }),
          ),
        ),
        // Always offered, not only when the entry point declared one: whether
        // this project has flavors is not something the cockpit knows, and a
        // flavoured project cannot be launched at all without the right word
        // here. Empty means no `--flavor` is passed.
        const Gap(FwSpacing.lg),
        _Field(
          label: 'Flavor',
          hint: 'the --flavor to build; leave empty if the project has none',
          child: TextField(
            controller: _flavor,
            style: context.type.bodySmall,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'dev, staging…',
            ),
          ),
        ),
        if (_knobs.isNotEmpty) ...[
          const Gap(FwSpacing.lg),
          _Field(
            label: 'Knobs',
            hint: 'compiled in — changing one is a rebuild',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var knob in _entry!.entry.knobs) ...[
                  _KnobField(
                    knob: knob,
                    options: _core.optionsFor(knob),
                    controller: _knobs[knob.define]!,
                  ),
                  const Gap(FwSpacing.md),
                ],
              ],
            ),
          ),
        ],
        const Gap(FwSpacing.lg),
        Row(
          children: [
            FilledButton(
              onPressed: _launching || device == null ? null : _start,
              child: Text(_launching ? 'Starting…' : 'Start'),
            ),
            const Gap(FwSpacing.md),
            // Said before the click, not explained after it: every wireless
            // launch in the spike stalled on an OS dialog while the tool
            // reported only `Installing and launching…`.
            if (device != null && device.isWireless)
              Flexible(
                child: Text(
                  'wireless — expect a slow install, and a permission prompt '
                  'on this Mac',
                  style: context.type.caption.copyWith(
                    color: context.colors.amber,
                  ),
                ),
              ),
          ],
        ),
        if (_error case var error?) ...[
          const Gap(FwSpacing.md),
          Text(
            error,
            style: context.type.caption.copyWith(color: context.colors.red),
          ),
        ],
        // Nothing is running, so the panel is where the desk lives for now.
        // It belongs in the shell's chrome — only the shell can jump you to
        // the worktree holding a busy device — but nobody who never looks up
        // there should lose the list.
        if (_core.handles.isEmpty) ...[
          const Gap(FwSpacing.xl),
          _Desk(core: _core),
        ],
      ],
    );
  }

  Future<void> _start() async {
    var choice = _entry;
    var device = _device;
    if (choice == null || device == null) return;
    var knobs = {
      for (var entry in _knobs.entries)
        if (entry.value.text.isNotEmpty) entry.key: entry.value.text,
    };
    var flavor = _flavor.text.trim();
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      var handle = await _core.launch(
        device: device,
        package: choice.package,
        entry: choice.entry,
        flavor: flavor.isEmpty ? null : flavor,
        knobs: knobs,
      );
      _core.lastLaunch = (
        device: device,
        package: choice.package,
        entrypoint: choice.entry.path,
        flavor: flavor.isEmpty ? null : flavor,
        knobs: knobs,
      );
      widget.onLaunched(handle);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not launch: $e');
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }
}

class _DevicePicker extends StatelessWidget {
  const _DevicePicker({
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  final List<DaemonDevice> devices;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return Text(
        'No devices yet. Starting a flutter daemon takes a few seconds.',
        style: context.type.bodyMuted,
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: devices.any((d) => d.id == selected) ? selected : null,
      isExpanded: true,
      items: [
        for (var device in devices)
          DropdownMenuItem(
            value: device.id,
            child: Row(
              children: [
                Flexible(
                  flex: 0,
                  child: Text(
                    device.displayName,
                    style: context.type.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Gap(FwSpacing.sm),
                Flexible(
                  child: Text(
                    _detail(device),
                    style: context.type.caption.copyWith(
                      color: context.colors.mut2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  static String _detail(DaemonDevice device) => [
    ?device.platformType,
    ?device.sdk,
    if (device.kind == MachineKind.virtual) 'simulator',
    if (device.isWireless) 'wireless',
    if (!device.isConnected) 'not connected',
  ].join(' · ');
}

/// A picker rather than a row of buttons.
///
/// Four to ten entry points as buttons is a wall; as a picker it is a line.
/// The description is what makes it usable: `Kiosk` and `Onboarding` cannot be
/// told apart by their file names.
class _EntrypointPicker extends StatelessWidget {
  const _EntrypointPicker({
    required this.entries,
    required this.selected,
    required this.onChanged,
  });

  final List<({String package, EntrypointRef entry})> entries;
  final ({String package, EntrypointRef entry})? selected;
  final ValueChanged<({String package, EntrypointRef entry})> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selected == null
          ? null
          : '${selected!.package}|${selected!.entry.path}',
      isExpanded: true,
      items: [
        for (var choice in entries)
          DropdownMenuItem(
            value: '${choice.package}|${choice.entry.path}',
            child: Row(
              children: [
                Flexible(
                  flex: 0,
                  child: Text(
                    choice.entry.name,
                    style: context.type.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Gap(FwSpacing.sm),
                Flexible(
                  child: Text(
                    choice.entry.description ?? choice.entry.path,
                    style: context.type.caption.copyWith(
                      color: context.colors.mut2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (value) {
        for (var choice in entries) {
          if ('${choice.package}|${choice.entry.path}' == value) {
            onChanged(choice);
            return;
          }
        }
      },
    );
  }
}

/// What is on this machine, and who has it.
///
/// The interim home of the desk: it belongs beside the worktree tabs, because a
/// busy device should take you to the worktree holding it and only the shell
/// can switch worktrees. Rendered here so the list exists before that lands.
class _Desk extends StatefulWidget {
  const _Desk({required this.core});

  final RunCore core;

  @override
  State<_Desk> createState() => _DeskState();
}

class _DeskState extends State<_Desk> {
  /// Which emulator is being booted, so its row can say so and nobody can
  /// press it twice into two boots of one machine.
  final _booting = <String>{};

  RunCore get core => widget.core;

  @override
  void initState() {
    super.initState();
    // A second round trip, asked for only when the desk is actually on screen.
    unawaited(core.loadEmulators());
  }

  Future<void> _boot(DaemonEmulator emulator) async {
    setState(() => _booting.add(emulator.id));
    try {
      await core.bootEmulator(emulator.id);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not boot ${emulator.displayName}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _booting.remove(emulator.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    // Only the ones not already up. `isEmulatorBooted` answers null for the
    // daemon's single iOS entry, which is a door to the Simulator rather than a
    // machine — that row stays, because opening the Simulator is useful whether
    // or not something is already in it.
    var offline = [
      for (var emulator in core.emulators)
        if (isEmulatorBooted(emulator, core.devices) != true) emulator,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('On this machine', style: context.type.fieldLabel),
            const Gap(FwSpacing.sm),
            Text(
              core.isLive ? 'live' : 'cached',
              style: context.type.micro.copyWith(color: colors.mut3),
            ),
          ],
        ),
        const Gap(FwSpacing.xs),
        for (var device in core.devices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(_iconFor(device), size: 14, color: colors.mut2),
                const Gap(FwSpacing.sm),
                Flexible(
                  flex: 0,
                  child: Text(
                    device.displayName,
                    style: context.type.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Gap(FwSpacing.sm),
                Text(
                  _status(device, core),
                  style: context.type.caption.copyWith(color: colors.mut2),
                ),
              ],
            ),
          ),
        for (var emulator in offline)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.phone_iphone_outlined, size: 14, color: colors.mut3),
                const Gap(FwSpacing.sm),
                Flexible(
                  flex: 0,
                  child: Text(
                    emulator.displayName,
                    style: context.type.bodySmall.copyWith(color: colors.mut2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Gap(FwSpacing.sm),
                if (_booting.contains(emulator.id))
                  Text(
                    'starting…',
                    style: context.type.caption.copyWith(color: colors.mut2),
                  )
                else
                  Tappable(
                    onTap: () => _boot(emulator),
                    child: Text(
                      // The iOS row opens the Simulator; an AVD row boots one
                      // machine. Different verbs because they are different
                      // acts.
                      emulator.platformType == 'ios' ? 'open' : 'boot',
                      style: context.type.caption.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// The three kinds, said in their own words — a host is never `free`,
  /// because it was never anybody's to take.
  static String _status(DaemonDevice device, RunCore core) {
    var holders = [
      for (var handle in core.handles)
        if (handle.device == device.id) handle,
    ];
    if (!device.isConnected) return 'not connected';
    if (holders.isEmpty) {
      return device.kind == MachineKind.host ? 'not running' : 'free';
    }
    var first = holders.first;
    return device.kind == MachineKind.host
        ? 'running ${first.runLabel}'
        : '${first.runLabel} · ${first.worktreeName}';
  }

  static IconData _iconFor(DaemonDevice device) => switch (device.kind) {
    MachineKind.host =>
      device.platformType == 'web'
          ? Icons.language_outlined
          : Icons.desktop_windows_outlined,
    MachineKind.virtual => Icons.phone_iphone_outlined,
    MachineKind.physical => Icons.smartphone_outlined,
  };
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint});

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(label, style: context.type.fieldLabel),
          if (hint != null) ...[
            const Gap(FwSpacing.sm),
            Flexible(
              child: Text(
                hint!,
                style: context.type.caption.copyWith(
                  color: context.colors.mut3,
                ),
              ),
            ),
          ],
        ],
      ),
      const Gap(FwSpacing.xs),
      child,
    ],
  );
}

/// The row above a pane: what it is, and how to take it again.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.loading, required this.onRefresh, this.note});

  final bool loading;
  final VoidCallback onRefresh;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: FwSpacing.lg,
      vertical: FwSpacing.xs,
    ),
    child: Row(
      children: [
        if (note != null)
          Flexible(
            child: Text(
              note!,
              style: context.type.micro.copyWith(color: context.colors.mut3),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const Spacer(),
        if (loading)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.mut2,
            ),
          )
        else
          _Action(
            'Refresh',
            Icons.refresh_rounded,
            enabled: true,
            onPressed: onRefresh,
          ),
      ],
    ),
  );
}

/// Where a run's page goes when the run never started.
///
/// Left-aligned, monospaced and scrollable rather than the centred one-liner
/// [_Failed] uses, because what goes here is a build failure: a fault, the file
/// it is in, and often the numbered steps that fix it. Centring that turns
/// instructions into a shrug.
class _FailedRunPage extends StatelessWidget {
  const _FailedRunPage({required this.failure, required this.onDismiss});

  final RunFailure failure;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(FwSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: colors.red),
              const Gap(FwSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failure.headline ?? 'The run did not start',
                      style: context.type.bodyStrong.copyWith(
                        color: colors.red,
                      ),
                    ),
                    const Gap(FwSpacing.xs),
                    Text(
                      '${failure.runLabel} on ${failure.deviceLabel} — '
                      'never started, so nothing is holding the device.',
                      style: context.type.bodyMuted,
                    ),
                  ],
                ),
              ),
              const Gap(FwSpacing.sm),
              TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FwSpacing.md),
            child: SelectableText(
              failure.message,
              style: _mono(context, color: colors.mut),
            ),
          ),
        ),
        if (failure.logPath case var path?) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(FwSpacing.sm),
            child: SelectableText(
              path,
              style: context.type.micro.copyWith(color: colors.mut3),
            ),
          ),
        ],
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FwSpacing.xl),
      child: SelectableText(
        message,
        textAlign: TextAlign.center,
        style: context.type.caption.copyWith(color: context.colors.red),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(FwSpacing.xl),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.type.bodyMuted,
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(
    this.label,
    this.icon, {
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      icon: Icon(icon, size: 16),
      onPressed: enabled ? onPressed : null,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
    ),
  );
}

/// What to bake in before building.
///
/// Every knob is a text field, because a `--dart-define` is a string; the
/// difference the tool makes is the list under it. `from: KnobSource.servers`
/// fills that list with the base URLs of the servers running right now, and
/// `hostAddresses` with this machine's LAN addresses — so "point the app at my
/// dev server" is a click rather than a trip to `ifconfig`.
class _KnobField extends StatelessWidget {
  const _KnobField({
    required this.knob,
    required this.options,
    required this.controller,
  });

  final LaunchKnob knob;
  final List<String> options;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(knob.label ?? knob.define, style: context.type.fieldLabel),
        if (knob.description != null)
          Text(knob.description!, style: context.type.caption),
        const Gap(FwSpacing.xxs),
        TextField(controller: controller),
        if (options.isNotEmpty) ...[
          const Gap(FwSpacing.xs),
          Wrap(
            spacing: FwSpacing.xs,
            runSpacing: FwSpacing.xxs,
            children: [
              for (var option in options)
                ActionChip(
                  label: Text(option, style: context.type.micro),
                  onPressed: () => controller.text = option,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: Text(label, style: context.type.micro.copyWith(color: colors.mut)),
    );
  }
}

/// The panel's one mono style, matching the server panel's: machine data —
/// log lines, paths — wears it, prose stays in the UI face.
TextStyle _mono(BuildContext context, {Color? color}) =>
    Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      letterSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color,
    );

/// `examples/example/lib/main.dart:66:11` — the part anybody reads.
///
/// The framework reports an absolute `file://` URI, which is the truth and is
/// also three times the width of the widget name beside it. Anything inside the
/// worktree becomes relative to it; anything outside is the SDK's own, where
/// the file and line are the only part that carries meaning.
String _sourceLabel(InspectSource source, String worktree) {
  var text = source.describe(relativeTo: worktree);
  if (!text.startsWith('/')) return text;
  var parts = text.split('/');
  return parts.length <= 2
      ? text
      : '…/${parts.sublist(parts.length - 2).join('/')}';
}
