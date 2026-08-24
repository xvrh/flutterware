import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../run/device/device_settings.dart';
import '../../run/device_strip.dart';
import '../../run/entrypoints.dart';
import '../../run/flavors.dart';
import '../../run/handle.dart';
import '../../run/inventory.dart';
import '../../run/flag_memory.dart';
import '../../run/journal.dart';
import '../../run/knob_field.dart';
import '../../run/knobs_tab.dart';
import '../../run/network_tab.dart';
import '../../run/panels_tab.dart';
import '../../run/screen_picture.dart';
import '../../run/launch.dart';
import '../../run/logs.dart';
import '../../run/native/native_logs.dart';
import '../../inspect/elements_view.dart';
import '../../inspect/inspect_dock.dart';
import '../../inspect/semantics_node.dart';
import '../../inspect/semantics_view.dart';
import '../../inspect/transcript.dart';

import '../../ui/capture_button.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/split_button.dart';
import '../../ui/empty_state.dart';
import '../../ui/loading_state.dart';
import '../../ui/popover.dart';
import '../../ui/popover_menu.dart';
import '../../ui/filter_bar.dart';
import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../../utils/daemon/device.dart';
import '../native_plugin.dart';
import 'run_address.dart';
import 'run_results.dart';
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
  ///
  /// Every branch here has to describe work that is **in flight**. A plugin is
  /// registered as a settle source for as long as its worktree session is open
  /// — not for as long as its panel is mounted — so a branch that reports busy
  /// because data is *missing* rather than *coming* holds up the capture of
  /// every other panel in the window, forever. See [RunCore.isFindingDevices]
  /// for the one that did.
  @override
  String? get busyWith {
    if (core.isFindingDevices) return 'finding devices';
    if (core.isStarting) return 'building';
    // The open pane is mid-read. Without this a capture settles on an empty
    // Screen tab saying `Reading the app…` — which is exactly what the first
    // review of this layout photographed, and it looked like the bug that had
    // just been fixed.
    if (_reading) return 'reading the app';
    return null;
  }

  var _reading = false;

  /// Told by the pane doing the reading. See [busyWith].
  void setReading(bool reading) {
    if (_reading == reading) return;
    _reading = reading;
    notifyChanged();
  }

  /// `+` beside `Run` in the rail.
  ///
  /// The runs themselves are the rail's child rows, so the one thing the list
  /// needs that a list of runs cannot express is *starting another*. Same shape
  /// as the scenarios panel's `+` on a folder header, one level up.
  @override
  List<PluginRowCommand> rowCommands() => const [
    PluginRowCommand(label: 'New run', icon: Icons.add, opens: newRunSegment),
  ];

  @override
  Widget buildPanel(BuildContext context) => _RunPanel(this);
}

/// Runs are the subjects here rather than devices.
///
/// The panel was a list of devices with a run squeezed into each row. That
/// fitted the first slice, strained in the second, and had nowhere to put the
/// third: a screenshot, a widget tree and a log stream do not go in a table
/// row. So it follows the server panel instead — subject chips, a tab strip,
/// and a pane — which is this problem already solved once in this codebase.
///
/// Starting a run is its own page rather than a button per entry point: four to
/// ten entry points as a row of buttons is a wall, and the defines have nowhere
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

  /// A config reload swaps the core under a panel that stays mounted.
  ///
  /// Rebuilding the session builds a new [RunCore]; the widget above this one
  /// keeps its position, so Flutter reuses this `State` and `initState` never
  /// runs again. Without this the new core is never tracked: `computeAll` does
  /// not run, so `entrypointsFor` stays empty and the panel says *no entry
  /// points* about a project that declares several — while an app launched
  /// from one of them is still running and still driveable. No daemon starts
  /// either, so the run vanishes from the cockpit and there is no way left to
  /// stop it. Saving `tool/flutterware.dart` was enough to get there.
  @override
  void didUpdateWidget(_RunPanel old) {
    super.didUpdateWidget(old);
    if (old.plugin != widget.plugin) _core.track();
  }

  RunPlace _resolve(BuildContext context) => runPlace(
    [for (var i = 0; i < 2; i++) AddressScope.segment(context, i) ?? '']
      ..removeWhere((s) => s.isEmpty),
  );

  /// The run the place names, or this worktree's first one.
  ///
  /// By key rather than by identity, because the handle object is replaced on
  /// every probe — and by *falling back* rather than by showing nothing,
  /// because an address to a run that has since stopped should land you in the
  /// cockpit rather than in an error.
  ///
  /// The two lookups scope differently on purpose. An explicit key finds any
  /// worktree's run — the read-only page exists precisely so a tool that
  /// knows will say. The fallback is own runs only: it used to be the newest
  /// handle on the machine, so opening Run in a fresh worktree landed you on
  /// whatever another checkout launched last.
  RunHandle? _select(List<RunHandle> handles, RunPlace place) {
    if (place.runKey case var key?) {
      for (var handle in handles) {
        if (handle.key == key) return handle;
      }
    }
    for (var handle in handles) {
      if (_core.isMine(handle)) return handle;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var handles = _core.handles;
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

        // No chip row. The runs are the rail's child rows and were being drawn
        // twice — the mockup had both, and building it made the duplication
        // plain. `+ New run` moved to the rail with them, as [rowCommands].
        return switch ((failed, shown)) {
          (var failure?, _) => _FailedRunPage(
            failure: failure,
            onDismiss: () {
              _core.dismissFailure(failure.key);
              if (mounted) {
                AddressScope.write(context).setSegments(const [newRunSegment]);
              }
            },
          ),
          (_, var handle?) => _RunView(
            core: _core,
            handle: handle,
            view: place.view,
            onControl: _control,
            onReading: widget.plugin.setReading,
          ),
          _ => _NewRunPage(core: _core, onLaunched: _goTo),
        };
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

/// One run: its tabs, its header, and whichever pane is open.
class _RunView extends StatefulWidget {
  const _RunView({
    required this.core,
    required this.handle,
    required this.view,
    required this.onControl,
    required this.onReading,
  });

  final RunCore core;
  final RunHandle handle;
  final RunViewKind view;
  final void Function(String action, RunHandle handle) onControl;

  /// Passed up to the plugin so `busyWith` can hold a capture until the pane
  /// has something worth photographing.
  final ValueChanged<bool> onReading;

  @override
  State<_RunView> createState() => _RunViewState();
}

class _RunViewState extends State<_RunView> {
  /// Lets the strip's refresh reach the open pane without lifting the pane's
  /// read into this widget. The strip belongs to the page and the reading
  /// belongs to the pane; this is the one wire between them.
  final _screen = GlobalKey<_ScreenTabState>();

  /// The device strip's, for the same reason: refresh means *read it all
  /// again*, and on the Screen view the device is half of what is on screen.
  final _device = GlobalKey<_DeviceStripHostState>();

  @override
  Widget build(BuildContext context) {
    var core = widget.core;
    var handle = widget.handle;
    var view = widget.view;
    var probe = core.probeOf(handle);
    var log = core.logOf(handle);
    var mine = handle.worktreeName == core.host.worktree.name;
    var state = _RunState.of(
      probe: probe,
      log: log,
      mine: mine,
      handle: handle,
    );

    // **Header first, then the tabs.** The design drew them the other way and
    // it read wrong once built: the run is the subject and the tabs are views
    // *of* it, so putting the strip on top made the page look like it belonged
    // to the tab rather than to the app you launched. Reload and stop act on
    // the run whichever pane is open, which is the same argument.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RunHeader(
          handle: handle,
          state: state,
          mine: mine,
          onControl: widget.onControl,
        ),
        _ViewTabs(
          runKey: handle.key,
          view: view,
          enabled: state.canInspect,
          busy:
              view == RunViewKind.screen &&
              (_screen.currentState?.isReading ?? false),
          onRefresh: view == RunViewKind.screen && state.canInspect
              ? () {
                  _screen.currentState?.read();
                  _device.currentState?.read();
                }
              : null,
          capture: view == RunViewKind.screen && state.canInspect
              ? CaptureButton(
                  primary: CaptureTarget(
                    label: 'the screenshot',
                    // The pane's last reading, resolved at click time — a
                    // null is the pane saying it has nothing yet, which ends
                    // the gesture quietly like any other empty capture.
                    capture: () async => _screen.currentState?.imageBytes,
                    suggestedName: () =>
                        '${handle.runLabel.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}'
                        '-screen.png',
                  ),
                )
              : null,
        ),
        const Divider(height: 1),
        // **Over the picture, not on a tab of its own.** A tab strip is
        // exclusive: opening a *Device* tab would close *Screen*, which is a
        // control writing to a page you are not on — the second dev-stack
        // study's finding 12. Here the result of pressing one is in the frame
        // underneath it.
        //
        // Outside the `switch` below, so it survives `!canInspect`: a device
        // answers while a build is running and after an app has died, which
        // makes this the second exception to the tab strip's disable after
        // Steps. What goes unknown in that window is the one setting derived
        // from the app's own geometry, and it says so.
        if (view == RunViewKind.screen)
          _DeviceStripHost(
            key: _device,
            core: core,
            handle: handle,
            canInspect: state.canInspect,
          ),
        Expanded(
          child: switch (view) {
            // The journal is a file: it answers while the app builds and
            // after it dies, which is exactly when a post-mortem review
            // wants it.
            RunViewKind.steps => _StepsTab(handle: handle),
            _ when !state.canInspect => _NotYet(state: state, handle: handle),
            RunViewKind.screen => _ScreenTab(
              key: _screen,
              core: core,
              handle: handle,
              clock: core.screenClockOf(handle),
              onReadingChanged: () {
                setState(() {});
                widget.onReading(_screen.currentState?.isReading ?? false);
              },
            ),
            RunViewKind.logs => _LogsTab(core: core, handle: handle),
            RunViewKind.network => NetworkTab(
              // Keyed by run, like the App tab: a different run behind the
              // same tab is a different app to attach to.
              key: ValueKey(handle.key),
              handle: handle,
            ),
            RunViewKind.knobs => _knobsTab(core, handle),
            RunViewKind.panels => PanelsTab(
              // Keyed by run: attaching is per app, and a different run behind
              // the same tab is a different app to attach to.
              key: ValueKey(handle.key),
              handle: handle,
              memory: FlagMemory(core.runDir),
            ),
          },
        ),
      ],
    );
  }
}

/// Capability, not liveness.
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
    var meta = [
      for (var define in handle.defines.entries)
        '${define.key}=${define.value}',
      'started ${describeAge(DateTime.now().difference(handle.startedAt))}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        FwSpacing.md,
        FwSpacing.md,
        FwSpacing.md,
      ),
      color: context.colors.panel2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${handle.runLabel} → ${handle.deviceLabel}',
                        style: context.type.heading,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Capability, as a pill rather than a caption — but only
                    // when it is news. "reloadable" is the normal state and
                    // the enabled buttons already say it; the pill appears
                    // when something is missing.
                    if (state.tone != _Tone.good) ...[
                      const Gap(FwSpacing.sm),
                      _CapabilityPill(state: state),
                    ],
                    if (!mine) ...[
                      const Gap(FwSpacing.sm),
                      _Tag(handle.worktreeName),
                    ],
                  ],
                ),
                const Gap(2),
                Text(
                  meta,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.caption.copyWith(color: colors.mut2),
                ),
              ],
            ),
          ),
          const Gap(FwSpacing.md),
          // Another worktree's run is shown read-only: it is useful to see, and
          // a tool that knew and would not say would be worse. Driving it is
          // its owner's business.
          if (mine)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FwSplitButton(
                  label: 'Hot reload',
                  icon: Icons.local_fire_department_rounded,
                  onPressed: state.canReload
                      ? () => onControl('reload', handle)
                      : null,
                  entries: [
                    MenuItem(
                      'Hot restart',
                      icon: Icons.restart_alt,
                      onSelected: state.canReload
                          ? () => onControl('restart', handle)
                          : null,
                    ),
                  ],
                ),
                const Gap(FwSpacing.xs),
                _Action(
                  'Stop',
                  Icons.stop_rounded,
                  enabled: true,
                  danger: true,
                  onPressed: () => onControl('stop', handle),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// What the run can still be told to do, in three words and a colour.
///
/// Capability, not liveness — the S-L1 finding made loud. An app whose
/// `flutter run` died keeps its tree and its screenshots and loses hot reload,
/// and the row has to say which of those you have before you press anything.
class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({required this.state});

  final _RunState state;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var color = switch (state.tone) {
      _Tone.good => colors.grn,
      _Tone.warn => colors.amber,
      _Tone.quiet => colors.mut2,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(context.radii.pill),
      ),
      child: Text(
        state.label,
        style: context.type.micro.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The Knobs tab: what this run's `main` was called with, editable.
///
/// One lookup rather than one per field — [RunCore.knobEntriesFor] parses the
/// entry point's signature once and answers with the knobs *or* the reason it
/// cannot know them, which are different things and drawn differently.
Widget _knobsTab(RunCore core, RunHandle handle) {
  var offered = core.knobEntriesFor(handle);
  return KnobsTab(
    handle: handle,
    knobs: offered.knobs,
    unknown: offered.unknown,
    onApply: (values) => core.applyKnobs(handle, values),
    interfaceOf: core.hostInterfaceOf,
  );
}

/// Screen | Logs, written into the address.
///
/// The strip is the extension point. `Network` and `Data` are devbar
/// plugins reporting into the cockpit later, so it has to accept tabs this
/// build does not know about — which is why the address carries a tab *name*
/// and reading an unknown one falls back to the screen.
///
/// [InspectTabStrip] rather than a row of buttons: it is what ui_catalog and
/// scenarios already draw above a widget tree, and three surfaces showing the
/// same thing should not be two designs.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({
    required this.runKey,
    required this.view,
    required this.enabled,
    this.busy = false,
    this.onRefresh,
    this.capture,
  });

  final String runKey;
  final RunViewKind view;

  /// The open pane's capture button, when it shows a picture worth exporting.
  final Widget? capture;

  /// False while the app has nothing to read. The tabs stay visible and stop
  /// responding — hiding them would move the page's furniture around every
  /// time a build started.
  final bool enabled;

  /// A reading is in flight; the spinner stands where the button was.
  final bool busy;

  /// Re-reads whatever the open pane shows. Null for a pane that has nothing
  /// to re-read — the log is read from the file on every build.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return InspectTabStrip(
      tabs: const [
        InspectDockTab(id: 'screen', label: 'Screen', body: _unused),
        InspectDockTab(id: 'steps', label: 'Steps', body: _unused),
        InspectDockTab(id: 'logs', label: 'Logs', body: _unused),
        InspectDockTab(id: 'network', label: 'Network', body: _unused),
        InspectDockTab(id: 'panels', label: 'App', body: _unused),
        InspectDockTab(id: 'knobs', label: 'Knobs', body: _unused),
      ],
      current: view.name,
      onSelect: (id) {
        // Steps is a file, like the log — readable before the app answers
        // and after it dies — so it never waits for the app.
        if (!enabled && id != 'steps') return;
        AddressScope.write(context).setSegments(
          runSegments(runKey, view: RunViewKind.byName(id) ?? view),
        );
      },
      // Where the dock puts it, so re-reading is in the same place on all
      // three surfaces. It had a row of its own, which held one icon and a
      // caption and floated between the header and the panes.
      trailing: [
        ?capture,
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: FwSpacing.sm),
            child: SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (onRefresh case var refresh?)
          InspectStripButton(
            icon: Icons.refresh,
            tooltip: 'Read it all again',
            onTap: refresh,
          ),
      ],
    );
  }

  /// The strip reads ids, labels and badges and never builds a body — the run
  /// page keeps its panes, because only one of them is cheap to rebuild.
  static Widget _unused(BuildContext context) => const SizedBox.shrink();
}

/// The device strip, with the reads and the writes behind it.
///
/// The Screen half of the split the launcher-icon research named: [DeviceStrip]
/// takes a list and two callbacks and reads nothing, and this holds the backend
/// and owns the busy state. Every ability it has is [RunCore]'s — the same two
/// methods `run/device` and `run/setDevice` call — so the panel adds nothing an
/// agent or the CLI cannot do.
class _DeviceStripHost extends StatefulWidget {
  const _DeviceStripHost({
    super.key,
    required this.core,
    required this.handle,
    required this.canInspect,
  });

  final RunCore core;
  final RunHandle handle;

  /// Whether the app is answering yet.
  ///
  /// Not an enable flag — the device answers either way, which is why this
  /// strip sits outside the tab strip's disable. It is a *read trigger*: the
  /// one setting whose value is derived from the app's own geometry cannot be
  /// known until there is an app, and the strip mounts while the build is
  /// still running.
  final bool canInspect;

  @override
  State<_DeviceStripHost> createState() => _DeviceStripHostState();
}

class _DeviceStripHostState extends State<_DeviceStripHost> {
  List<DeviceSetting> _settings = const [];

  /// What the strip has to say that no chip can hold — in v1, the refusal from
  /// a target with no backend, which names what would work instead.
  String? _notice;

  var _reading = false;
  final _busy = <DeviceSettingId>{};

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(_DeviceStripHost old) {
    super.didUpdateWidget(old);
    // A different run in the same slot is a different device, not a stale
    // reading of this one.
    if (old.handle.key != widget.handle.key) {
      _settings = const [];
      _notice = null;
      _busy.clear();
      unawaited(_read());
      return;
    }
    // **The app started answering, so one of these has an answer now.** The
    // strip mounts while the build is still running — that is the point of it
    // being outside the disable — and at that moment `orientation` on an iOS
    // simulator is honestly unknown, because it is read from the running app's
    // width and height and there is no running app. Left there, the chip went
    // on saying `—` beside a tree reporting 402×874. Measured on a real
    // simulator, 2026-08-24.
    if (widget.canInspect && !old.canInspect) unawaited(_read());
  }

  /// Public so the tab strip's refresh can reach it, the way it reaches the
  /// picture beside it.
  Future<void> read() => _read();

  Future<void> _read() async {
    // Assigned rather than `setState`, because this is reached from `initState`
    // and `didUpdateWidget`, both of which run inside a build.
    _reading = true;
    try {
      var settings = await widget.core.readDeviceSettings(widget.handle);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _notice = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      // A refusal is the strip's whole content on a target with no backend, and
      // it is drawn rather than hidden: a control that vanishes reads as an
      // oversight, and the sentence names the mechanism that would work.
      setState(() {
        _settings = const [];
        _notice = '$e';
      });
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _set(DeviceSettingId id, String value) async {
    setState(() => _busy.add(id));
    try {
      var written = await widget.core.writeDeviceSetting(
        widget.handle,
        id,
        value,
      );
      if (!mounted) return;
      // Spliced rather than followed by a second full read, and the reason is
      // that the reply already **is** the read: `writeDeviceSetting` answers
      // with that setting re-read from the command that owns it. A second pass
      // over the other seven would be seven subprocesses asking about settings
      // this write cannot have touched.
      setState(() {
        _settings = [
          for (var setting in _settings)
            if (setting.id == id) written else setting,
        ];
        _notice = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _notice = '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => DeviceStrip(
    settings: _settings,
    notice: _notice,
    reading: _reading,
    busy: _busy,
    // Null only where there is nothing to write to. A dead app is not that:
    // the device answers either way, which is the whole reason this sits
    // outside the tab strip's disable.
    onSet: _settings.isEmpty ? null : _set,
  );
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
            'Nothing can be read until the app starts. A cold build can '
            'take a few minutes.',
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

/// The picture and the widget tree, side by side — the design's Screen tab.
///
/// One reading rather than two. Both come off a single `getRootWidgetTree` in
/// one object group, which is what merging `inspect` into one action allowed: a
/// live app animates and takes in data between calls, so two reads would put a
/// tree beside a picture of a different frame.
///
/// It is not a live mirror, and the UI shows that. Each capture is a render and
/// a PNG — 66ms on this Mac, 42 on a simulator — so polling would run
/// continuously for a screen that is mostly not being watched. A button is the
/// right shape until a mirror is worth the cost.
class _ScreenTab extends StatefulWidget {
  const _ScreenTab({
    super.key,
    required this.core,
    required this.handle,
    required this.clock,
    required this.onReadingChanged,
  });

  final RunCore core;
  final RunHandle handle;

  /// What the cockpit knows about the app moving — see
  /// [RunCore.screenClockOf]. Read here rather than in the pane so that a
  /// rebuild is the only wire: the page already rebuilds on every core
  /// notification, and `didUpdateWidget` is where a pane is told what changed.
  final (int moved, int byCockpit) clock;

  /// So the strip above can swap its refresh button for a spinner. The pane
  /// owns the reading; the page only needs to know one is happening.
  final VoidCallback onReadingChanged;

  @override
  State<_ScreenTab> createState() => _ScreenTabState();
}

class _ScreenTabState extends State<_ScreenTab> {
  Uint8List? _image;

  /// The same picture, decoded — see [_Picture] for why the pane is handed a
  /// frame rather than the bytes it came in.
  ui.Image? _picture;
  var _undecodable = false;
  InspectTree? _tree;

  /// Whether [_tree] came from the app's own walk — see
  /// [InspectRead.fromGuest]. It decides what an empty field in the detail
  /// pane is allowed to mean, which is why it is carried rather than guessed
  /// at from whether some node happens to have a box.
  var _fromGuest = false;
  String? _error;
  var _loading = false;

  /// When the reading on screen was taken, and what the cockpit's `moved`
  /// count stood at then. Together they are the caption: how old the picture
  /// is, and whether anything has reported a change it does not show.
  DateTime? _readAt;
  var _readAtMoved = 0;

  /// The dock's open tab, and whether it is folded away.
  ///
  /// Held here rather than in the address: which reading of the screen is open
  /// is a posture rather than a place, and putting it in the URL would make
  /// the back button undo a glance.
  var _tab = 'elements';
  var _collapsed = false;

  bool get isReading => _loading;

  /// The last reading's picture, for the strip's capture button — bytes the
  /// pane already holds, so exporting one costs no round trip to the app.
  Uint8List? get imageBytes => _image;

  /// What the tree hovers, for the box drawn over the picture.
  ///
  /// Only a guest tree can be drawn. The service extension carries no
  /// position at all — `getLayoutExplorerNode` gives size and constraints,
  /// `parentData` is `<none>` — so a run the cockpit merely attached to has
  /// no rect to draw and the picture stays a picture. Nothing here tests for
  /// that: a node with no `layout` paints nothing, which is the same answer
  /// arrived at without a second flag to keep in step.
  final _highlight = ValueNotifier<String?>(null);

  /// The Semantics tab's own hover, and its reading-order switch.
  ///
  /// Separate from [_highlight] because they are hovers of different trees:
  /// a widget's box comes off [InspectLayout], an utterance's off the
  /// semantics node's own rect, and one notifier holding either would have to
  /// say which every time it was read.
  final _semanticsHighlight = ValueNotifier<SemanticsSnapshotNode?>(null);
  final _focusOrder = ValueNotifier<bool>(false);

  SemanticsSnapshotNode? _semantics;
  SemanticsTranscript? _transcript;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_ScreenTab old) {
    super.didUpdateWidget(old);
    // A different run in the same tab is a different subject, not a stale
    // picture of this one.
    if (old.handle.key != widget.handle.key) {
      _image = null;
      _picture?.dispose();
      _picture = null;
      _undecodable = false;
      _tree = null;
      _fromGuest = false;
      _semantics = null;
      _transcript = null;
      _semanticsHighlight.value = null;
      _error = null;
      _readAt = null;
      _readAtMoved = 0;
      _read();
      return;
    }
    // **What the cockpit did, the cockpit shows.** A hot reload, a restart or
    // a drive step is the user asking for the app to be different; leaving a
    // picture of the old one up is the pane disagreeing with the button that
    // was just pressed.
    //
    // A human's own taps deliberately do *not* land here. They arrive through
    // the beat poller at up to one batch a second, and re-reading on each
    // would be a render and a full tree walk per tap — polling, wearing a
    // finger. Those move `moved` alone, and the caption says so.
    if (widget.clock.$2 != old.clock.$2 && !_loading) _read();
  }

  @override
  void dispose() {
    _picture?.dispose();
    _highlight.dispose();
    _semanticsHighlight.dispose();
    _focusOrder.dispose();
    super.dispose();
  }

  /// Public so the tab strip's refresh can reach it — see [_RunViewState].
  Future<void> read() => _read();

  Future<void> _read() async {
    // Assigned rather than `setState`, because this is reached from `initState`
    // and `didUpdateWidget` — both inside a build. [_tellThePage] schedules the
    // rebuild that shows it, one frame later, which is what a spinner is for.
    _loading = true;
    _tellThePage();
    try {
      // **Semantics in the same reading, not when the tab opens.** One read
      // is what makes the boxes over the picture exact — a semantics tree
      // fetched later would describe a frame the picture is not of — and it
      // is what makes switching tabs free rather than a second round trip
      // through the app.
      var read = await widget.core.inspectRead(widget.handle, semantics: true);
      // Decoded here rather than in the pane, so that the frame and the caption
      // describing it land in the same build. The picture already on screen is
      // held until this one is ready — a re-read should not blank the pane it
      // is refreshing.
      var picture = await _decodePicture(read.image);
      if (!mounted) {
        picture?.dispose();
        return;
      }
      setState(() {
        _picture?.dispose();
        _image = read.image;
        _picture = picture;
        _undecodable = read.image != null && picture == null;
        _tree = read.tree;
        _fromGuest = read.fromGuest;
        // Typed here rather than in the reading, because the reading is
        // linked by `fw` and the MCP server and a `Rect` is `dart:ui`.
        _semantics = switch (read.semantics?.root) {
          var root? => SemanticsSnapshotNode.fromJson(root),
          _ => null,
        };
        // Derived once per reading rather than per build: the tab badge wants
        // the finding count whether or not the tab is open, and the view would
        // otherwise walk the tree again to get it.
        _transcript = _semantics == null
            ? null
            : SemanticsTranscript.of(_semantics!);
        _semanticsHighlight.value = null;
        _error = null;
        _readAt = DateTime.now();
        // The count as it stands *now*, not as it stood when the read was
        // asked for: a tap that arrived while the picture was being taken is
        // a tap the picture may well show.
        _readAtMoved = widget.clock.$1;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _tellThePage();
      }
    }
  }

  /// After the frame, never inside it. The page above draws the spinner in
  /// its tab strip, so this is a `setState` on an *ancestor* — and [_read] is
  /// reached from `initState` and `didUpdateWidget`, both of which run while
  /// that ancestor is building. In debug the framework throws there, which
  /// aborted the read before it started and left the pane saying `Reading the
  /// app…` for ever.
  ///
  /// It survived review because `capture` builds the GUI in **release**, where
  /// the assertion is compiled out and the same call merely schedules a
  /// rebuild. A screenshot is not a test of this class of bug.
  void _tellThePage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReadingChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error case var error?) return _Failed(error);
    // One state for one thing. The dock draws a grip and a strip for a tree
    // that is not there yet, which reads as furniture waiting for a panel
    // rather than as a pane that is busy — so until the first reading lands
    // there is nothing here but the sentence saying so.
    if (_loading && _image == null && _tree == null) {
      return const LoadingState(
        title: 'Reading the app…',
        message: 'Its widget tree, and a picture of what it is showing.',
      );
    }
    // **The picture on top, the tree docked under it** — what previews and the
    // scenarios step page draw, and now the third surface drawing it.
    //
    // What it costs is worth writing down, because it was measured and it is
    // real: at 872×737 the dock draws a desktop app at 475×384 where a
    // third-of-the-width column managed 280×227, and pays for it in tree —
    // about eleven rows at the dock's resting height against thirty-two beside
    // a column. The grip is the answer to that: the dock resizes and
    // collapses, so the trade is the reader's to make per task, where a fixed
    // column was nobody's.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RunScreenPicture(
              picture: _picture,
              undecodable: _undecodable,
              loading: _loading,
              highlight: _highlight,
              tree: _tree,
              canvas: RunScreenPicture.canvasOf(_tree),
              semanticsHighlight: _semanticsHighlight,
              focusOrder: _focusOrder,
              // Only while the Semantics tab is the one showing — its toggle
              // is the only way to turn the numbers off, so they must not
              // outlive it.
              focusNodes: _tab == 'semantics'
                  ? _transcript?.utterances.map((u) => u.node).toList()
                  : null,
              readAt: _readAt,
              movedSince: widget.clock.$1 != _readAtMoved,
            ),
          ),
          InspectDock(
            available: constraints.maxHeight,
            current: _tab,
            collapsed: _collapsed,
            onChanged: (current, collapsed) => setState(() {
              _tab = current;
              _collapsed = collapsed;
            }),
            // No refresh of its own: the page's strip already carries one and
            // it re-reads both halves. Two buttons for one reading would be
            // two claims about what a reading is.
            tabs: [
              InspectDockTab(
                id: 'elements',
                label: 'Elements',
                body: (context) => _elements(),
              ),
              InspectDockTab(
                id: 'semantics',
                label: 'Semantics',
                badge: _transcript?.findingCount ?? 0,
                body: (context) => SemanticsView(
                  root: _semantics,
                  transcript: _transcript,
                  highlight: _semanticsHighlight,
                  focusOrder: _focusOrder,
                  // Three absences, and they are not the same news. A run the
                  // cockpit merely attached to has no guest to ask; a run that
                  // has one is holding a `SemanticsHandle` for its whole life,
                  // so an empty tree there is the app's own answer.
                  placeholder: _loading
                      ? 'Reading the app…'
                      : !_fromGuest
                      ? 'This run has no flutterware guest in it, and the '
                            'service extension has no semantics to give. '
                            'Launch it through flutterware to read them.'
                      : 'The app has published no semantics tree.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The tree and its detail pane, side by side — the dock's one tab.
  Widget _elements() => ElementsView(
    root: _tree?.root,
    placeholder: _loading
        ? 'Reading the app…'
        : 'The app has not built a frame yet.',
    highlight: _highlight,
    // Paths are shortened against the worktree, and live in the detail pane
    // rather than on every row — which is what the shared view does and what
    // the run panel's own tree did not.
    displayRoot: widget.core.host.worktree.path,
    // Per read, because this pane has two sources. The VM service hands out
    // structure and creation locations and nothing else; the guest walks the
    // app's own elements, so on a run launched through flutterware a node with
    // no box really has none. Said here rather than inferred from empty fields.
    readsWidgets: _fromGuest,
  );
}

/// Bytes to a frame, or null.
///
/// Absence is a null and never an exception, which is the contract the
/// comparison side's shot decoding already settled on: a picture that will not
/// decode is a thing the pane has to *say*, and a throw here would report it as
/// a failed read instead.
Future<ui.Image?> _decodePicture(Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    var codec = await ui.instantiateImageCodec(bytes);
    var frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } on Object {
    return null;
  }
}

/// Re-reads a file-backed tab the moment its file changes.
///
/// A watch on the file's directory (the pattern the server tracker uses),
/// debounced because one step is several writes, with a poll underneath: a
/// watch can be unavailable (directory not there yet, filesystem without
/// events) and a tab that silently stopped updating would read as a dead run.
/// The poll runs slow when the watch is live and at the watchless tabs' old
/// cadence when it is not.
class _FileRefresh {
  _FileRefresh(String? path, this.onChanged) {
    if (path != null) {
      var directory = File(path).parent;
      if (directory.existsSync()) {
        _watch = directory.watch().listen((event) {
          if (!event.path.startsWith(path)) return;
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 50), onChanged);
        }, onError: (_) {});
      }
    }
    _poll = Timer.periodic(
      _watch != null
          ? const Duration(seconds: 2)
          : const Duration(milliseconds: 700),
      (_) => onChanged(),
    );
  }

  final void Function() onChanged;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;
  Timer? _poll;

  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    unawaited(_watch?.cancel());
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
  List<RunLogLine> _lines = const [];
  _FileRefresh? _refresh;

  /// The platform log, once it has been asked for.
  ///
  /// A fetch rather than a filter, which the tab shows by loading. The other
  /// three pills narrow a file this tab already holds; this one spends a `log
  /// show` or an `adb logcat` against the device. Selecting it is the request,
  /// and selecting it again refreshes — there is nothing to poll, because
  /// unlike the launcher's log nothing here changes on disk.
  NativeLogRead? _native;
  var _readingNative = false;

  @override
  void initState() {
    super.initState();
    _reread();
    _refresh = _FileRefresh(widget.handle.logPath, _reread);
  }

  @override
  void didUpdateWidget(_LogsTab old) {
    super.didUpdateWidget(old);
    if (old.handle.key != widget.handle.key) {
      _refresh?.dispose();
      _refresh = _FileRefresh(widget.handle.logPath, _reread);
      _native = null;
      _reread();
      // A different run is a different device: what was read for the last one
      // says nothing about this one, and an empty list would read as "it
      // logged nothing" rather than as "nobody has asked yet".
      if (_only == RunLogSource.native) unawaited(_rereadNative());
    }
  }

  @override
  void dispose() {
    _refresh?.dispose();
    super.dispose();
  }

  /// Not in `build`. A log is a file, the panel rebuilds on every probe and
  /// on every frame of any animation above it, and `RunCore.logOf` says in as
  /// many words why a panel must not read one from there. [_FileRefresh] is
  /// the right shape: the file changing is what makes this stale.
  void _reread() {
    if (!mounted) return;
    var lines = widget.core.readLogs(widget.handle, only: _only, tail: 2000);
    setState(() => _lines = lines);
  }

  /// Never on [_FileRefresh]. The launcher's log file changes constantly while
  /// an app runs, and this spawns a process: hanging it off the same callback
  /// would fire a `log show` every poll. It runs on request — which is what
  /// selecting the filter is.
  Future<void> _rereadNative() async {
    setState(() => _readingNative = true);
    var read = await widget.core.readNativeLogs(widget.handle, tail: 2000);
    if (!mounted) return;
    setState(() {
      _native = read;
      _readingNative = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    var native = _only == RunLogSource.native;
    var lines = native ? _native?.lines ?? const <RunLogLine>[] : _lines;
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
                ('Platform', RunLogSource.native),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: FwSpacing.xs),
                  child: FwPill(
                    label: label,
                    selected: _only == value,
                    onTap: () {
                      _only = value;
                      // Immediately, not on the next tick: a filter that took
                      // most of a second to answer would read as broken.
                      if (value == RunLogSource.native) {
                        unawaited(_rereadNative());
                      } else {
                        _reread();
                      }
                    },
                  ),
                ),
              const Spacer(),
              Text(
                _readingNative ? 'reading…' : '${lines.length} lines',
                style: context.type.micro.copyWith(color: context.colors.mut3),
              ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? _Hint(switch (_only) {
                  RunLogSource.app =>
                    'The app has printed nothing. The build output is '
                        'under Build.',
                  RunLogSource.native =>
                    _readingNative
                        ? 'Asking the platform…'
                        : _native?.note ??
                              'The native half of this app has logged '
                                  'nothing.',
                  _ => 'Nothing logged yet.',
                })
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

/// The run's journal, reviewable: what the tools did to this app, step by
/// step, each with its screenshot.
///
/// The human half of co-driving. An agent taps, types, reloads and observes
/// from CLI or MCP; its steps land here with their pictures, so "then I look
/// and confirm" is a scroll rather than an act of faith. A file like the log,
/// polled like the log, and readable while the app builds and after it dies.
class _StepsTab extends StatefulWidget {
  const _StepsTab({required this.handle});

  final RunHandle handle;

  @override
  State<_StepsTab> createState() => _StepsTabState();
}

class _StepsTabState extends State<_StepsTab> {
  var _entries = const <JournalEntry>[];

  /// Which step is open. Null follows the newest as more arrive — the state
  /// the tab opens in, and returns to when you select the last row.
  int? _selected;

  _FileRefresh? _refresh;

  @override
  void initState() {
    super.initState();
    _reread();
    _refresh = _FileRefresh(journalPathFor(widget.handle), _reread);
  }

  @override
  void didUpdateWidget(_StepsTab old) {
    super.didUpdateWidget(old);
    if (old.handle.key != widget.handle.key) {
      _selected = null;
      _refresh?.dispose();
      _refresh = _FileRefresh(journalPathFor(widget.handle), _reread);
      _reread();
    }
  }

  @override
  void dispose() {
    _refresh?.dispose();
    super.dispose();
  }

  /// Not in `build`, for the same reason the log tab says: the journal is a
  /// file, and the panel rebuilds far more often than the file changes.
  void _reread() {
    if (!mounted) return;
    var entries = readJournal(widget.handle, tail: 500);
    setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    var entries = _entries;
    if (entries.isEmpty) {
      return const _Hint(
        'Nothing has driven this run yet. Steps land here when an agent — '
        'or fw — taps, types, reloads or observes.',
      );
    }
    var selected = (_selected ?? entries.length - 1).clamp(
      0,
      entries.length - 1,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          // `reverse` pins the newest step, which is the one anybody opening
          // the journal came to see — the log tab's argument, unchanged.
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              var index = entries.length - 1 - i;
              return _StepRow(
                entry: entries[index],
                ordinal: index + 1,
                selected: index == selected,
                onTap: () => setState(
                  () => _selected = index == entries.length - 1 ? null : index,
                ),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _StepDetail(entry: entries[selected])),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.entry,
    required this.ordinal,
    required this.selected,
    required this.onTap,
  });

  final JournalEntry entry;
  final int ordinal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var caption = [
      ?entry.actor,
      // Which tree the step addressed belongs in the caption, not a detail
      // pane: a native tap and a widget tap look identical in a thumbnail,
      // and "the agent went below the widget tree" is usually the
      // interesting part of a review rather than a footnote.
      ?entry.layer,
      _clock(entry.at),
      if ((entry.attempts ?? 1) > 1) '${entry.attempts} tries',
      if (entry.settled == false) 'did not settle',
    ].join(' · ');
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.md,
          vertical: FwSpacing.xs,
        ),
        color: selected ? colors.accentSoft : null,
        child: Row(
          children: [
            _thumbnail(context),
            const Gap(FwSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$ordinal · ${stepSentence(entry)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.bodySmall.copyWith(
                      color: entry.error != null ? colors.red : colors.ink,
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.micro.copyWith(color: colors.mut3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(BuildContext context) {
    var path = entry.screenshot;
    if (path != null && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(context.radii.micro),
        child: Image.file(
          File(path),
          width: 44,
          height: 32,
          fit: BoxFit.cover,
          cacheWidth: 88,
          gaplessPlayback: true,
        ),
      );
    }
    return SizedBox(
      width: 44,
      height: 32,
      child: Icon(
        _verbIcon(entry.verb),
        size: FwIconSize.lg,
        color: context.colors.mut2,
      ),
    );
  }
}

/// The step's face: the screenshot big, the facts above it, the refusal in
/// red when there was one, and the text projection when there is no picture.
class _StepDetail extends StatefulWidget {
  const _StepDetail({required this.entry});

  final JournalEntry entry;

  @override
  State<_StepDetail> createState() => _StepDetailState();
}

class _StepDetailState extends State<_StepDetail> {
  List<String>? _texts;
  String? _textsPath;

  /// Reads the step's texts artifact once per step — the step-page's rule:
  /// the file is already on disk and small, so a synchronous read from the
  /// lifecycle, never a spinner.
  void _loadTexts() {
    var path = widget.entry.texts;
    if (path == _textsPath) return;
    _textsPath = path;
    _texts = null;
    if (path == null) return;
    try {
      _texts = (jsonDecode(File(path).readAsStringSync()) as List)
          .cast<String>();
    } on Object {
      _texts = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _loadTexts();
    var entry = widget.entry;
    var colors = context.colors;
    var facts = [
      if (entry.actor case var actor?) 'by $actor',
      if (entry.layer case var layer?) 'through the $layer layer',
      if (entry.reconciled case var count? when count > 0)
        '$count of its own taps came back as human input, and were dropped',
      if ((entry.attempts ?? 1) > 1) '${entry.attempts} tries',
      if (entry.settleMs case var ms?) 'settled in ${ms}ms',
      if (entry.settled == false) 'still animating when observed',
      if (entry.lifecycle case var lifecycle? when lifecycle != 'resumed')
        lifecycle,
      if (entry.logLines case var lines? when lines > 0)
        '$lines log line${lines == 1 ? '' : 's'}',
      if (entry.errorCount case var count? when count > 0)
        '$count error${count == 1 ? '' : 's'}',
    ];
    var screenshot = entry.screenshot;
    var hasShot = screenshot != null && File(screenshot).existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.lg,
            FwSpacing.md,
            FwSpacing.lg,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(stepSentence(entry), style: context.type.body),
                  ),
                  if (hasShot)
                    CaptureButton(
                      primary: CaptureTarget(
                        label: "the step's screenshot",
                        capture: () => File(screenshot).readAsBytes(),
                        // The journal already names the file after the step;
                        // a save keeps that identity.
                        suggestedName: () => p.basename(screenshot),
                      ),
                    ),
                ],
              ),
              if (facts.isNotEmpty) ...[
                const Gap(FwSpacing.xxs),
                Text(
                  facts.join(' · '),
                  style: context.type.caption.copyWith(color: colors.mut2),
                ),
              ],
              if (entry.error case var error?) ...[
                const Gap(FwSpacing.sm),
                SelectableText(
                  error,
                  style: context.type.bodySmall.copyWith(color: colors.red),
                ),
              ],
            ],
          ),
        ),
        const Gap(FwSpacing.md),
        Expanded(
          child: hasShot
              ? Container(
                  color: colors.bg,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(FwSpacing.md),
                  child: Image.file(
                    File(screenshot),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                )
              : _texts == null
              ? const _Hint('This step kept no picture.')
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.lg,
                    vertical: FwSpacing.sm,
                  ),
                  children: [
                    for (var text in _texts!)
                      if (text.isNotEmpty)
                        SelectableText(text, style: _mono(context)),
                  ],
                ),
        ),
      ],
    );
  }
}

/// `tap "Pay"` — the one spelling the errors, the journal and the strip
/// share.
String stepSentence(JournalEntry entry) =>
    entry.target == null ? entry.verb : '${entry.verb} ${entry.target}';

IconData _verbIcon(String verb) => switch (verb) {
  'tap' ||
  'doubleTap' ||
  'longPress' ||
  'secondaryTap' => Icons.touch_app_outlined,
  'hover' || 'unhover' => Icons.mouse_outlined,
  'drag' => Icons.swipe_outlined,
  'scroll' || 'scrollTo' => Icons.swap_vert,
  'enterText' => Icons.keyboard_outlined,
  'key' => Icons.keyboard_alt_outlined,
  'back' => Icons.arrow_back,
  'wait' => Icons.hourglass_empty,
  'observe' => Icons.visibility_outlined,
  'navigate' => Icons.route_outlined,
  'reload' => Icons.local_fire_department_outlined,
  'restart' => Icons.restart_alt,
  'stop' => Icons.stop_outlined,
  'launch' => Icons.play_arrow_outlined,
  _ => Icons.circle_outlined,
};

/// `14:03:59` from an ISO timestamp, local time — enough to line steps up
/// against the log.
String _clock(String iso) {
  var time = DateTime.tryParse(iso)?.toLocal();
  if (time == null) return '';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}

/// Pick an entry point, pick a device it can run on, fill its defines, start.
///
/// One column, in that order, and it opens filled in with whatever ran last —
/// so running the same thing again is opening the page and pressing Start.
/// An earlier draft had a two-column workspace with a recents row; it was
/// harder to follow than the four steps it was decorating.
///
/// The entry point comes first, and the fields below depend on it. It was
/// second, under the device, which had the dependency backwards: an entry point
/// declaring `platforms: [mobile]` decides which devices are offerable and
/// what flavor is pre-filled, so choosing it after them meant choosing them
/// twice. Flavor and defines were already downstream of it; the device list is
/// the third thing that was pretending not to be.
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
  final _flavor = TextEditingController();

  /// True once the user has taken the flavor off what the project declares.
  ///
  /// The field is collapsed to a line of text until then, because the answer is
  /// nearly always already written down — in the entry point, or in the
  /// package's `flutter: default-flavor:` — and an empty box beside it invited
  /// filling in something the project had settled two files away.
  var _overridingFlavor = false;
  var _launching = false;

  /// What the form has been told to pass `main`, by parameter name. Absent
  /// means "left alone", which is not the same as empty — the parameter's own
  /// default then applies and nothing is written into the wrapper.
  final _knobs = <String, String>{};
  String? _error;

  RunCore get _core => widget.core;

  List<({String package, EntrypointRef entry})> get _entries => [
    for (var package in _core.packages)
      for (var entry in _core.entrypointsFor(package))
        (package: package, entry: entry),
  ];

  @override
  void dispose() {
    _flavor.dispose();
    super.dispose();
  }

  /// Fills the form from the last launch, and from the first plausible choice
  /// when there has not been one.
  void _prime() {
    var entries = _entries;
    if (entries.isEmpty) return;
    var last = _core.lastLaunch;
    if (_entry == null) {
      var restored = entries
          .where(
            (e) =>
                e.package == last?.package && e.entry.path == last?.entrypoint,
          )
          .firstOrNull;
      _entry = restored ?? entries.first;
      // Only when it really is last time's entry point. The knobs and the
      // flavor of a run belong to the `main()` they were typed for, and
      // restoring them onto whatever entry point happened to sort first put a
      // stale flavor on an unrelated build.
      _rebuildKnobs(restored != null ? last?.knobs ?? const {} : const {});
      // The device before the flavor, because the flavor can depend on it —
      // an entry point pairing `patientLocal` with `mobile` pre-fills
      // differently for a phone than for this machine.
      _device ??= _pickDevice(preferred: last?.device);
      _resetFlavor(used: restored != null ? last?.flavor : null);
    }
    _device ??= _pickDevice(preferred: last?.device);
  }

  /// The declared flavor, unless [used] records an override.
  ///
  /// Matching the declaration is not an override, so a run launched without
  /// touching the field reopens the page collapsed rather than expanded on a
  /// value it would have used anyway.
  void _resetFlavor({String? used}) {
    var declared = _declaredFlavor.flavor;
    _overridingFlavor = used != null && used.isNotEmpty && used != declared;
    _flavor.text = (_overridingFlavor ? used : declared) ?? '';
  }

  ({String? flavor, FlavorSource source}) get _declaredFlavor {
    var choice = _entry;
    return choice == null
        ? (flavor: null, source: FlavorSource.none)
        : _core.flavorFor(choice.package, choice.entry, device: _device);
  }

  /// The device to select: the one asked for when this entry point allows it,
  /// otherwise the first connected one that it does.
  String? _pickDevice({String? preferred}) {
    var choice = _entry;
    if (choice == null) return null;
    var allowed = _core.devicesFor(choice.entry);
    if (allowed.any((device) => device.id == preferred)) return preferred;
    return allowed
            .where((device) => device.isConnected)
            .map((device) => device.id)
            .firstOrNull ??
        allowed.firstOrNull?.id;
  }

  /// Why the device list is shorter than the desk, when it is.
  ///
  /// Said rather than left to be noticed: a picker that has quietly dropped
  /// the machine you were about to choose is indistinguishable from a tool
  /// that has not found it yet.
  String? get _restriction {
    var platforms = _entry?.entry.platforms ?? const [];
    if (platforms.isEmpty) return null;
    return '${_entry!.entry.name} runs on '
        '${[for (var platform in platforms) platform.name].join(', ')}';
  }

  /// Seeds each field with what the *last launch chose*, and nothing else.
  ///
  /// A default is shown as a hint, not as text. The field's content is what
  /// gets sent, and `launch` fills in the defaults itself — so pre-filling one
  /// here would send it back as an explicit choice, which is how the panel and
  /// the action used to disagree about the same launch. An empty field now
  /// means "whatever the default is", which is also what it looks like.
  /// The caller decides whether [values] belong here: a knob set for one entry
  /// point means nothing on another, because they are different signatures.
  /// [_prime] passes an empty map for exactly that case.
  void _rebuildKnobs(Map<String, String> values) {
    _knobs
      ..clear()
      ..addAll(values);
  }

  /// The knobs this entry point's `main` takes, as the cockpit and the
  /// `entrypoints` action both see them. Through the core for the same reason
  /// a control only the panel had would be one an agent could not see.
  List<RunKnobEntry> get _offeredKnobs {
    var choice = _entry;
    return choice == null
        ? const []
        : _core.knobEntriesOf(choice.package, choice.entry);
  }

  /// Why Start is off, when a knob is the reason.
  ///
  /// Asked of the core rather than worked out from [_offeredKnobs], so the
  /// button and the `launch` it calls cannot disagree: a form that let this be
  /// pressed would spend a build finding out what the same rule already knows.
  String? get _knobsProblem {
    var choice = _entry;
    return choice == null
        ? null
        : _core.requiredKnobsProblem(choice.package, choice.entry, _knobs);
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
    var allowed = _entry == null
        ? _core.devices
        : _core.devicesFor(_entry!.entry);
    var device = allowed.where((d) => d.id == _device).firstOrNull;
    // Read once for the button and the sentence beside it: two readings could
    // grey out Start and then explain nothing.
    var blocked = _knobsProblem;
    // A column, not the window. Fields stretched across a desktop panel put
    // the label and the caret a hand's width apart, and the form is a short
    // sequence of decisions rather than a table.
    // The scroller is the whole pane; the cap sits inside it. The other way
    // round — a ListView *inside* the 560 cap — parks the scroll gutter 560px
    // from the left, which on a wide window reads as a divider down the middle
    // of the page rather than as the edge of a list.
    return ListView(
      padding: const EdgeInsets.all(FwSpacing.xl),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New run', style: context.type.heading),
                const Gap(FwSpacing.lg),
                _Field(
                  label: 'Entry point',
                  child: _EntrypointPicker(
                    entries: entries,
                    selected: _entry,
                    onChanged: (choice) => setState(() {
                      _entry = choice;
                      _rebuildKnobs(const {});
                      _resetFlavor();
                      // Everything below is downstream, and the device most
                      // visibly so: switching to a mobile-only entry point while
                      // this Mac is selected has to move off it, not leave a
                      // selection the Start button would refuse.
                      _device = _pickDevice(preferred: _device);
                    }),
                  ),
                ),
                const Gap(FwSpacing.lg),
                _Field(
                  label: 'Device',
                  hint: _restriction,
                  child: _DevicePicker(
                    devices: allowed,
                    selected: _device,
                    restricted: _entry?.entry.platforms.isNotEmpty ?? false,
                    onChanged: (id) => setState(() {
                      _device = id;
                      // The declared flavor can differ per device; a value the
                      // user typed over it stays theirs.
                      if (!_overridingFlavor) _resetFlavor();
                    }),
                  ),
                ),
                // Always present, not only when something declared one: whether
                // this project has flavors is not something the cockpit knows, and
                // a flavoured project cannot be launched at all without the right
                // word here.
                const Gap(FwSpacing.lg),
                _Field(
                  label: 'Flavor',
                  hint: _overridingFlavor
                      ? 'just this run; empty passes no --flavor at all'
                      : null,
                  child: _FlavorField(
                    declared: _declaredFlavor,
                    vocabulary: _entry == null
                        ? null
                        : _core.flavorVocabularyFor(_entry!.package, _device),
                    controller: _flavor,
                    overriding: _overridingFlavor,
                    onOverride: () => setState(() => _overridingFlavor = true),
                    onRevert: () => setState(_resetFlavor),
                    onPicked: (choice) => setState(() => _flavor.text = choice),
                  ),
                ),
                if (_offeredKnobs.isNotEmpty) ...[
                  const Gap(FwSpacing.lg),
                  _Field(
                    label: 'Knobs',
                    hint: 'passed to main — changing one is a hot restart',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var knob in _offeredKnobs) ...[
                          KnobField(
                            knob: knob,
                            value: _knobs[knob.name],
                            interfaceOf: _core.hostInterfaceOf,
                            onChanged: (value) => setState(() {
                              if (value == null) {
                                _knobs.remove(knob.name);
                              } else {
                                _knobs[knob.name] = value;
                              }
                            }),
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
                      onPressed: _launching || device == null || blocked != null
                          ? null
                          : _start,
                      child: Text(_launching ? 'Starting…' : 'Start'),
                    ),
                    const Gap(FwSpacing.md),
                    // Said before the click, not explained after it: every wireless
                    // launch in the spike stalled on an OS dialog while the tool
                    // reported only `Installing and launching…`.
                    if (blocked case var reason?)
                      Flexible(
                        child: Text(
                          reason,
                          style: context.type.caption.copyWith(
                            color: context.colors.amber,
                          ),
                        ),
                      )
                    else if (device != null && device.isWireless)
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
                    style: context.type.caption.copyWith(
                      color: context.colors.red,
                    ),
                  ),
                ],
                // The desk also lives in the shell's chrome, where it can jump you
                // to the worktree holding a busy device — but nobody who never
                // looks up there should lose the list. Gated on *this worktree's*
                // runs: another checkout holding the phone is exactly when the
                // desk has something to say here.
                if (_core.ownHandles.isEmpty) ...[
                  const Gap(FwSpacing.xl),
                  _Desk(core: _core),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// What the fields above say, in the shape a launch takes them.
  ///
  /// One reading rather than one per button. The matrix launches the same app
  /// Start does, and it read the *declared* flavor and no knobs while Start
  /// read the form — so a flavor typed into the field, or a knob the entry
  /// point needs, was honoured by one button and silently dropped by the
  /// other.
  ({String? flavor, Map<String, String> knobs}) get _choices => (
    flavor: _flavor.text.trim().isEmpty ? null : _flavor.text.trim(),
    knobs: {..._knobs},
  );

  Future<void> _start() async {
    var choice = _entry;
    var device = _device;
    if (choice == null || device == null) return;
    var (:flavor, :knobs) = _choices;
    setState(() {
      _launching = true;
      _error = null;
    });
    try {
      var handle = await _core.launch(
        device: device,
        package: choice.package,
        entry: choice.entry,
        flavor: flavor,
        knobs: knobs,
      );
      _core.lastLaunch = (
        device: device,
        package: choice.package,
        entrypoint: choice.entry.path,
        flavor: flavor,
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
    this.restricted = false,
  });

  final List<DaemonDevice> devices;
  final String? selected;
  final ValueChanged<String> onChanged;

  /// Whether [devices] is the desk filtered by an entry point's declaration.
  ///
  /// Only the empty state needs it, and it needs it badly: "starting a flutter
  /// daemon takes a few seconds" is wrong for a desk that is full of machines
  /// this entry point said it cannot use.
  final bool restricted;

  @override
  Widget build(BuildContext context) => _Picker<String>(
    choices: [
      for (var device in devices)
        _Choice(
          value: device.id,
          label: device.displayName,
          detail: _detail(device),
          // The same green the rail uses for a live run. A phone that went to
          // sleep is still listed and is not launchable, and the row should say
          // so before the click rather than the build after it.
          dotColor: device.isConnected
              ? context.colors.grn
              : context.colors.mut3,
          enabled: device.isConnected,
        ),
    ],
    selected: selected,
    onChanged: onChanged,
    empty: restricted
        ? 'Nothing connected that this entry point can run on. Boot one from '
              'the desk below, or widen its platforms in tool/flutterware.dart.'
        : 'No devices yet. Starting a flutter daemon takes a few seconds.',
  );

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
  Widget build(BuildContext context) => _Picker<String>(
    choices: [
      for (var choice in entries)
        _Choice(
          value: _idOf(choice),
          label: choice.entry.name,
          // The description when the config wrote one, the path when it did
          // not. Never both — the path is what a description exists to replace.
          detail: choice.entry.description ?? choice.entry.path,
        ),
    ],
    selected: selected == null ? null : _idOf(selected!),
    onChanged: (id) {
      for (var choice in entries) {
        if (_idOf(choice) == id) {
          onChanged(choice);
          return;
        }
      }
    },
    empty: 'No entry points.',
  );

  static String _idOf(({String package, EntrypointRef entry}) choice) =>
      '${choice.package}|${choice.entry.path}';
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
  /// Which emulator is being booted, so its row can show it and a second press
  /// cannot start a second boot of one machine.
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
                Icon(_iconFor(device), size: FwIconSize.sm, color: colors.mut2),
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
                Icon(
                  Icons.phone_iphone_outlined,
                  size: FwIconSize.sm,
                  color: colors.mut3,
                ),
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

/// The `--flavor`: a line of text until it needs changing.
///
/// A text box was the wrong shape for a field that is right before you look at
/// it. The project has almost always said which flavor this entry point builds
/// with — in `Entrypoint(flavor:)`, or in its pubspec's `default-flavor` — so
/// the ordinary job here is *reading* one word and moving on, and an empty box
/// beside a declared value invites retyping it.
///
/// Overriding stays one click away, because the case that needs it is real:
/// running the one entry point under a second flavor without declaring it
/// twice. Where the package declares its flavors ([vocabulary]), overriding is
/// picking off that list rather than typing — the launch would refuse an
/// unlisted word anyway, and a picker shows that before the attempt. A platform
/// declared flavorless collapses the field to that one fact.
class _FlavorField extends StatelessWidget {
  const _FlavorField({
    required this.declared,
    required this.vocabulary,
    required this.controller,
    required this.overriding,
    required this.onOverride,
    required this.onRevert,
    required this.onPicked,
  });

  final ({String? flavor, FlavorSource source}) declared;

  /// The declared flavors for the selected device's platform — null where the
  /// package declares nothing, empty where it declares "none here".
  final List<String>? vocabulary;

  final TextEditingController controller;
  final bool overriding;
  final VoidCallback onOverride;
  final VoidCallback onRevert;

  /// A pick from the vocabulary — the dropdown writes through this rather
  /// than into [controller] directly so the page can rebuild around it.
  final void Function(String) onPicked;

  @override
  Widget build(BuildContext context) {
    if (vocabulary?.isEmpty == true) {
      // Nothing to read, nothing to override: the declaration says this
      // platform has no flavors, and the launch drops the flag the way web
      // does. An Override button here could only produce a refused launch.
      return Text(
        'none — the platform declares no flavors',
        style: context.type.caption.copyWith(color: context.colors.mut3),
      );
    }
    if (overriding) {
      var options = vocabulary;
      return Row(
        children: [
          // Capped and unstyled, so this is the same control as a knob's: no
          // `style:` override (which made it 27 tall beside a 32 field on the
          // same form) and the same width as a knob value, since a flavor is
          // one word and 500px of box for `dev` reads as a mistake.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KnobField.controlWidth,
              ),
              // The declared list where there is one — same control as an
              // enum knob's, and only values the list actually holds, for the
              // same reason: a dropdown asked to show a value it has no item
              // for asserts rather than degrading.
              child: options == null
                  ? TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'dev, staging…',
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: options.contains(controller.text)
                          ? controller.text
                          : null,
                      isDense: true,
                      items: [
                        for (var option in options)
                          DropdownMenuItem(value: option, child: Text(option)),
                      ],
                      onChanged: (choice) {
                        if (choice != null) onPicked(choice);
                      },
                    ),
            ),
          ),
          const Gap(FwSpacing.xs),
          TextButton(
            onPressed: onRevert,
            child: Text(
              declared.flavor == null ? 'Clear' : 'Use ${declared.flavor}',
              style: context.type.caption,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Text(
          declared.flavor ?? 'none',
          style: declared.flavor == null
              ? context.type.bodySmall.copyWith(color: context.colors.mut3)
              : context.type.bodySmall,
        ),
        const Gap(FwSpacing.sm),
        Flexible(
          child: Text(switch (declared.source) {
            FlavorSource.entrypoint => 'from the entry point',
            FlavorSource.pubspec => 'from the pubspec’s default-flavor',
            // Not "the project has none": a project can have flavors and
            // simply not have written this down, and that is exactly the
            // case where the build is about to fail for a reason the
            // cockpit could not have known.
            FlavorSource.none => 'nothing declares one — none is passed',
          }, style: context.type.caption.copyWith(color: context.colors.mut3)),
        ),
        const Gap(FwSpacing.xs),
        TextButton(
          onPressed: onOverride,
          child: Text('Override', style: context.type.caption),
        ),
      ],
    );
  }
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
              Icon(Icons.error_outline, size: FwIconSize.md, color: colors.red),
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

/// A control on the run's header — icon and word, not a bare glyph.
class _Action extends StatelessWidget {
  const _Action(
    this.label,
    this.icon, {
    required this.enabled,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool danger;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var fg = !enabled
        ? colors.mut3
        : danger
        ? colors.red
        : colors.accent;
    return Padding(
      padding: const EdgeInsets.only(left: FwSpacing.xs),
      child: Tappable(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.sm,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(context.radii.radiusSmall),
            border: Border.all(color: colors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: FwIconSize.sm, color: fg),
              const Gap(FwSpacing.xs),
              Text(label, style: context.type.bodySmall.copyWith(color: fg)),
            ],
          ),
        ),
      ),
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

/// One choice, as the New run page offers it: a bold name, a muted line under
/// it, and an optional dot.
class _Choice<T> {
  const _Choice({
    required this.value,
    required this.label,
    this.detail,
    this.dotColor,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// What the name does not say — `ios · iOS 26.5 · wireless`, or an entry
  /// point's description. The whole reason a picker beats a list of file names.
  final String? detail;

  final Color? dotColor;
  final bool enabled;
}

/// The New run page's picker: a trigger that reads like a field, and a popover
/// of rows with room for a description.
///
/// Not `DropdownButtonFormField`. Both pickers were one, which put a device
/// and an entry point through a control with one line of text and Material 3's
/// own paddings. The design draws a bordered box — name, detail, caret —
/// opening onto two-line rows, and `Kiosk` and `Onboarding` are unguessable
/// from their file names, which is the entire reason this is a picker.
///
/// Built on [Popover] and [PopoverMenuSurface], which this app already has:
/// both were ported from `cms/packages/admin_ui`, which is where the shape
/// comes from, and the scenarios panel already uses them.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.choices,
    required this.selected,
    required this.onChanged,
    required this.empty,
  });

  final List<_Choice<T>> choices;
  final T? selected;
  final ValueChanged<T> onChanged;

  /// Said instead of an empty box — a device list still being read is a
  /// different thing from a project with no entry points.
  final String empty;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    if (choices.isEmpty) return Text(empty, style: context.type.bodyMuted);
    var current = choices
        .where((choice) => choice.value == selected)
        .firstOrNull;

    return Popover(
      anchor: (context, controller) => Tappable.builder(
        onTap: controller.toggle,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.md,
            vertical: FwSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(context.radii.radius),
            border: Border.all(
              color: controller.isOpen
                  ? colors.accent
                  : hovered
                  ? colors.mut3
                  : colors.line,
            ),
          ),
          child: Row(
            children: [
              if (current?.dotColor case var color?) ...[
                Icon(Icons.circle, size: 8, color: color),
                const Gap(FwSpacing.sm),
              ],
              Flexible(
                flex: 0,
                child: Text(
                  current?.label ?? 'Choose…',
                  style: context.type.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (current?.detail case var detail?) ...[
                const Gap(FwSpacing.sm),
                Flexible(
                  child: Text(
                    detail,
                    style: context.type.caption.copyWith(color: colors.mut),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              const Gap(FwSpacing.sm),
              Icon(Icons.expand_more, size: FwIconSize.md, color: colors.mut2),
            ],
          ),
        ),
      ),
      content: (context, controller) => PopoverMenuSurface(
        // The trigger's width, so the open list lines up under the field
        // rather than floating at whatever its longest row wants.
        width: controller.anchorWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FwSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var choice in choices)
                _PickerRow<T>(
                  choice: choice,
                  selected: choice.value == selected,
                  onTap: () {
                    controller.close();
                    onChanged(choice.value);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final _Choice<T> choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable(
      onTap: choice.enabled ? onTap : null,
      borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : null,
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        ),
        child: Row(
          children: [
            if (choice.dotColor case var color?) ...[
              Icon(
                Icons.circle,
                size: 8,
                color: choice.enabled ? color : colors.mut3,
              ),
              const Gap(FwSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    choice.label,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? colors.accent
                          : choice.enabled
                          ? colors.ink
                          : colors.mut2,
                    ),
                  ),
                  if (choice.detail case var detail?)
                    Text(
                      detail,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.micro.copyWith(color: colors.mut),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
