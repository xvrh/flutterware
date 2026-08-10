import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../previews/catalog_session.dart';
import '../../previews/compiler_daemon_client.dart';
import '../../embedder/embedded_engine.dart';
import '../../motion/discovery.dart';
import '../../motion/lane_model.dart';
import '../../motion/new_span.dart';
import '../../motion/values_file.dart';
import '../../ui/design/spacing.dart';
import '../../ui/design/tokens.dart';
import '../../ui/tappable.dart';
import '../native_plugin.dart';
import 'motion_address.dart';
import 'motion_core.dart';
import 'motion_sequencer.dart';

export 'motion_core.dart' show MotionCore, motionPluginId;

/// The GUI half of the motion plugin: a band naming which motion you are on,
/// that motion running in a live guest, and a sequencer under it.
///
/// **The panel owns no truth.** The list comes from the core's syntactic scan,
/// and everything under the preview — targets, properties, states, current
/// values — comes from `ext.flutterware.motion.list` against the guest, which
/// is the runtime deciding rather than the panel inferring.
class MotionPlugin extends NativePlugin<MotionCore> {
  MotionPlugin(super.core);

  @override
  String? get busyWith =>
      core.packages.any(core.isScanning) ? 'scanning motions' : null;

  @override
  Widget buildPanel(BuildContext context) => _MotionPanel(this);
}

class _MotionPanel extends StatefulWidget {
  const _MotionPanel(this.plugin);

  final MotionPlugin plugin;

  @override
  State<_MotionPanel> createState() => _MotionPanelState();
}

class _MotionPanelState extends State<_MotionPanel> {
  MotionCore get _core => widget.plugin.core;

  /// The place the address names, or the first declared package when it names
  /// none — where selecting the plugin off the rail leaves you.
  MotionPlace? _resolve() {
    var t = AddressScope.param(context, 't');
    if (motionPlace(AddressScope.segments(context), t: t) case var place?) {
      return place;
    }
    var package = _core.packages.firstOrNull;
    return package == null ? null : MotionPlace(package, t: _parseT(t));
  }

  static double? _parseT(String? raw) => switch (double.tryParse(raw ?? '')) {
    var value? when value >= 0 && value <= 1 => value,
    _ => null,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolve() case var place?) _core.track(place.package);
  }

  @override
  Widget build(BuildContext context) {
    var place = _resolve();
    if (place == null) {
      return Center(
        child: Text(
          'No packages configured for this plugin.\n'
          'Add them in tool/flutterware.dart.',
          textAlign: TextAlign.center,
          style: context.type.bodyMuted,
        ),
      );
    }

    var result = _core.resultFor(place.package);
    var selected = _selectedMotion(result, place);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MotionBand(
          core: _core,
          place: place,
          result: result,
          selected: selected,
        ),
        Divider(height: 1, color: context.colors.line),
        Expanded(child: _body(context, place, result, selected)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    MotionPlace place,
    MotionScanResult? result,
    MotionRef? selected,
  ) {
    if (_core.errorFor(place.package) case var error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.lg),
          child: Text(
            '$error',
            style: context.type.body.copyWith(color: context.colors.red),
          ),
        ),
      );
    }
    if (result == null) {
      return Center(child: Text('Scanning…', style: context.type.bodyMuted));
    }
    if (result.motions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.lg),
          child: Text(
            'No MotionScope found in ${_core.directoryFor(place.package)}.',
            textAlign: TextAlign.center,
            style: context.type.bodyMuted,
          ),
        ),
      );
    }
    if (selected == null) {
      return Center(
        child: Text(
          'Select a motion to scrub it.',
          style: context.type.bodyMuted,
        ),
      );
    }
    return _MotionStage(
      key: ValueKey('${place.package}/${selected.file}'),
      core: _core,
      place: place,
      motion: selected,
    );
  }

  MotionRef? _selectedMotion(MotionScanResult? result, MotionPlace place) {
    var motions = result?.motions ?? const <MotionRef>[];
    if (motions.isEmpty) return null;
    for (var motion in motions) {
      if (motion.file == place.file &&
          (place.motion == null || motion.values == place.motion)) {
        return motion;
      }
    }
    return place.file == null ? motions.first : null;
  }
}

/// The header: which motion, what the scan could not read, and which file the
/// editor writes.
///
/// **This replaces a 280px list down the left side.** The shell's address bar
/// already names the motion you are on, so a permanent list was the same
/// identity twice — the argument that killed the separate target rail, one
/// level up. The room goes to the stage and the inspector, which are the two
/// things you actually look at.
class _MotionBand extends StatelessWidget {
  const _MotionBand({
    required this.core,
    required this.place,
    required this.result,
    required this.selected,
  });

  final MotionCore core;
  final MotionPlace place;
  final MotionScanResult? result;
  final MotionRef? selected;

  @override
  Widget build(BuildContext context) {
    var motions = result?.motions ?? const <MotionRef>[];
    var diagnostics = result?.diagnostics ?? const <String>[];

    return Container(
      height: 42,
      color: context.colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.lg),
      child: Row(
        spacing: FwSpacing.md,
        children: [
          if (motions.isEmpty)
            Text('Motion', style: context.type.bodyMuted)
          else
            _MotionPicker(
              core: core,
              place: place,
              motions: motions,
              selected: selected,
            ),
          // Never an aside, and never behind anything: a target named by an
          // expression is invisible to the scan and perfectly real at run time,
          // so a picker that listed only what it could parse would read as
          // complete and be wrong.
          if (diagnostics.isNotEmpty) _ScanGaps(diagnostics),
          const Spacer(),
          if (selected case var motion?)
            _ValuesFileBadge(
              p.basename(core.valuesPathFor(place.package, motion.file)),
            ),
        ],
      ),
    );
  }
}

class _MotionPicker extends StatelessWidget {
  const _MotionPicker({
    required this.core,
    required this.place,
    required this.motions,
    required this.selected,
  });

  final MotionCore core;
  final MotionPlace place;
  final List<MotionRef> motions;
  final MotionRef? selected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (var motion in motions)
          MenuItemButton(
            onPressed: () => AddressScope.of(context).go(
              core.addressFor(
                place.package,
                file: motion.file,
                motion: motion.values,
                t: place.t,
              ),
            ),
            leadingIcon: Icon(
              identical(motion, selected) ? Icons.check : null,
              size: 14,
              color: context.colors.accent,
            ),
            child: Row(
              spacing: FwSpacing.lg,
              children: [
                Text(motion.values ?? '<expression>', style: context.type.body),
                Text(
                  '${p.basename(motion.file)}:${motion.line} · '
                  '${motion.targets.length} target'
                  '${motion.targets.length == 1 ? '' : 's'}',
                  style: context.type.caption.copyWith(
                    color: context.colors.mut,
                  ),
                ),
              ],
            ),
          ),
      ],
      builder: (context, controller, _) => Tappable(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          spacing: FwSpacing.xs,
          children: [
            Text(
              selected?.values ?? 'Select a motion',
              style: context.type.body.copyWith(fontWeight: FontWeight.w600),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: context.colors.mut2,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the scan could not read, one click from the name it sits beside.
class _ScanGaps extends StatelessWidget {
  const _ScanGaps(this.diagnostics);

  final List<String> diagnostics;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (var diagnostic in diagnostics)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.lg,
              vertical: FwSpacing.xs,
            ),
            child: SizedBox(
              width: 420,
              child: Text(
                diagnostic,
                style: context.type.caption.copyWith(
                  color: context.colors.amber,
                ),
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message:
            'Read the code, could not resolve it. These targets are real '
            'at run time and absent from every list here.',
        child: Tappable(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: context.colors.amber.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${diagnostics.length} not scanned',
              style: context.type.caption.copyWith(color: context.colors.amber),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one file the editor writes, named where you can see it.
///
/// Blast radius zero is the promise the whole design rests on, and a promise
/// nobody can see is one nobody can check.
class _ValuesFileBadge extends StatelessWidget {
  const _ValuesFileBadge(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'The only file this editor writes.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: context.colors.accentSoft,
          border: Border.all(color: context.colors.accent),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          name,
          style: context.type.caption.copyWith(color: context.colors.accent),
        ),
      ),
    );
  }
}

/// One motion, running.
class _MotionStage extends StatefulWidget {
  const _MotionStage({
    super.key,
    required this.core,
    required this.place,
    required this.motion,
  });

  final MotionCore core;
  final MotionPlace place;
  final MotionRef motion;

  @override
  State<_MotionStage> createState() => _MotionStageState();
}

class _MotionStageState extends State<_MotionStage> {
  CatalogSession? _session;
  Timer? _poll;
  Timer? _tick;

  /// The guest's own answer, or null before it has given one.
  Map<String, dynamic>? _scope;

  /// What the slider is showing while a drag is in flight.
  ///
  /// The guest is the truth and it answers *after the frame*, so echoing it
  /// straight back would make the thumb lag the finger by a frame on every
  /// sample. Held locally for the duration of the drag and dropped after.
  double? _dragging;

  var _seeking = false;
  var _ticking = false;

  /// Why the last write was refused, or empty. Shown rather than swallowed: a
  /// drag that silently does nothing is worse than one that says why.
  List<MotionFileProblem> _writeProblems = const [];

  /// Which span the inspector is showing, as an address rather than a
  /// reference — the poll replaces the model underneath it every second.
  MotionSelection? _selection;

  /// Whether the inspector is up, once somebody has said. Null means "whatever
  /// there is room for".
  bool? _showRail;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    var core = widget.core;
    var package = widget.place.package;
    var session = CatalogSession(
      appPackageRoot: core.host.workspace.appContext.appToolDirectory.path,
      flutterSdkRoot: core.host.workspace.flutterSdk.root,
      projectRoot: p.join(core.host.worktree.path, package),
      worktreeRoot: core.host.worktree.path,
      roots: [core.directoryFor(package)],
      connectToDaemon: CompilerDaemonClient.connect,
    )..addListener(_onSession);
    _session = session;
    unawaited(session.start());
    // Slow, because none of this is a live readout: the states and the tuned
    // spans change when somebody edits a file, not between frames.
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    // The playhead is the exception, and it needs its own rate. `list` walks
    // every target and segment, so polling *it* fast is not an option; the
    // guest answers `progress` with three numbers instead.
    _tick = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _followPlayhead(),
    );
  }

  void _onSession() {
    if (!mounted) return;
    // The entry whose source file is the one the motion was scanned from.
    var session = _session!;
    if (session.phase == CatalogSessionPhase.ready &&
        session.wantedEntryId == null) {
      for (var entry in session.entries) {
        if (entry.path == widget.motion.file) {
          session.wantedEntryId = entry.id;
          break;
        }
      }
    }
    setState(() {});
  }

  /// Follows a playing motion, and asks nothing at all when none is.
  ///
  /// Idle, this costs one boolean read every 40ms. The alternative — ticking
  /// only while a transport is in flight — needs the panel to know when the
  /// motion *ended*, which is the thing it is asking about.
  Future<void> _followPlayhead() async {
    if (_ticking || _dragging != null) return;
    if (_scope == null || _scope!['playing'] != true) return;
    _ticking = true;
    try {
      var reply = await _session?.callGuestExtension(
        'ext.flutterware.motion.progress',
      );
      if (!mounted || reply == null) return;
      // Merged rather than replacing: the lanes stay put while the playhead
      // moves, so a scrub does not make every lane flicker.
      setState(() => _scope = {..._scope!, ...reply});
    } finally {
      _ticking = false;
    }
  }

  Future<void> _refresh() async {
    var listed = await _session?.callGuestExtension(
      'ext.flutterware.motion.list',
    );
    if (!mounted) return;
    var scopes = (listed?['scopes'] as List?)?.cast<Map<String, dynamic>>();
    setState(
      () => _scope = scopes == null || scopes.isEmpty ? null : scopes.first,
    );
  }

  /// One seek, and never two at once.
  ///
  /// A drag samples far faster than a guest can draw, and queueing every sample
  /// would leave the preview finishing a scrub you abandoned seconds ago. The
  /// last position always lands because the drag end seeks again.
  Future<void> _seek(double t) async {
    setState(() => _dragging = t);
    if (_seeking) return;
    _seeking = true;
    try {
      var reply = await _session?.callGuestExtension(
        'ext.flutterware.motion.seek',
        args: {'t': '$t'},
      );
      if (!mounted || reply == null) return;
      // The values change with the playhead; the lanes do not. Refreshing the
      // whole tree on every drag sample is what makes a scrubber feel heavy.
      await _refresh();
    } finally {
      _seeking = false;
    }
  }

  /// Retimes one span and writes the file.
  ///
  /// Everything here is a whole-file read, one span replaced, a whole-expression
  /// write — no incremental model to keep in step with the disk, because the
  /// disk is the model. The guest picks the edit up through the ordinary
  /// reload; nothing is pushed into it.
  Future<void> _edit(
    String target,
    String property,
    int index,
    MotionSpan Function(MotionSpan) change,
  ) async {
    var core = widget.core;
    var package = widget.place.package;
    var file = widget.motion.file;
    var read = core.readValues(package, file, constName: widget.motion.values);
    if (!read.writable) {
      setState(() => _writeProblems = read.problems);
      return;
    }

    var targets = [
      for (var existing in read.file!.targets)
        if (existing.name != target)
          existing
        else
          MotionTargetValues(
            name: existing.name,
            comments: existing.comments,
            blankBefore: existing.blankBefore,
            properties: [
              for (var candidate in existing.properties)
                if (candidate.name != property)
                  candidate
                else
                  MotionPropertyValues(
                    name: candidate.name,
                    comments: candidate.comments,
                    blankBefore: candidate.blankBefore,
                    spans: [
                      for (var (i, span) in candidate.spans.indexed)
                        i == index ? change(span) : span,
                    ],
                  ),
            ],
          ),
    ];

    await _commit(targets);
  }

  /// Gives a lane another tween — and what that means depends on whether it has
  /// one.
  ///
  /// On an untuned lane it is the creation path the three states exist for:
  /// reached from a dashed lane (read in code, untuned) or from a target's
  /// offered list (a `MotionBox` applies it, nothing tunes it), and both are the
  /// same act — the code already asks for the value, and this is where the
  /// value starts existing.
  ///
  /// On a tuned one it inserts at the playhead, opening at whatever the guest
  /// says the property is worth there.
  Future<void> _create(String target, String property) async {
    var core = widget.core;
    var read = core.readValues(
      widget.place.package,
      widget.motion.file,
      constName: widget.motion.values,
    );
    if (!read.writable) {
      setState(() => _writeProblems = read.problems);
      return;
    }

    var scope = MotionScopeView.parse(_scope);
    var existing = scope?.property(target, property);
    var durationMs = scope?.durationMs;

    if (existing == null || existing.segments.isEmpty) {
      var span = newSpanFor(property, durationMs: durationMs);
      if (span == null) {
        setState(
          () => _writeProblems = [
            MotionFileProblem('`$property` is not a motion property'),
          ],
        );
        return;
      }
      await _commit(
        withNewProperty(read.file!.targets, target, property, span),
      );
      return;
    }

    var atMs = ((_dragging ?? scope!.progress) * scope!.durationMs).round();
    var span = spanFor(
      property: property,
      atMs: atMs,
      durationMs: scope.durationMs,
      existing: [
        for (var segment in existing.segments) (segment.startMs, segment.endMs),
      ],
      current: _literalOf(existing.value),
    );
    // Only reachable when the lane is covered end to end, which is a thing to
    // say plainly rather than a millisecond to report back.
    if (span == null) {
      setState(
        () => _writeProblems = [
          MotionFileProblem(
            '$target.$property is tuned end to end; shorten or delete a '
            'span to make room for another.',
          ),
        ],
      );
      return;
    }
    await _commit(withSpanAdded(read.file!.targets, target, property, span));
  }

  /// What the guest says a property is worth, as the file would spell it.
  static MotionLiteral? _literalOf(MotionValueView? value) => switch (value) {
    MotionColorView(:var argb) => MotionColor(argb),
    MotionNumberView(:var value) => MotionNumber(value),
    null => null,
  };

  Future<void> _delete(MotionSelection selection) async {
    var core = widget.core;
    var read = core.readValues(
      widget.place.package,
      widget.motion.file,
      constName: widget.motion.values,
    );
    if (!read.writable) {
      setState(() => _writeProblems = read.problems);
      return;
    }
    setState(() => _selection = null);
    await _commit(
      withSpanRemoved(
        read.file!.targets,
        selection.target,
        selection.property,
        selection.index,
      ),
    );
  }

  Future<void> _commit(List<MotionTargetValues> targets) async {
    var problems = widget.core.writeValues(
      widget.place.package,
      widget.motion.file,
      targets,
      constName: widget.motion.values,
    );
    if (!mounted) return;
    setState(() => _writeProblems = problems);
    if (problems.isEmpty) {
      await _session?.reloadIfChanged();
      await _refresh();
    }
  }

  Future<void> _transport(String verb) async {
    await _session?.callGuestExtension(
      'ext.flutterware.motion.transport',
      args: {'verb': verb},
    );
    await _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _session?.removeListener(_onSession);
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var session = _session;
    var scope = MotionScopeView.parse(_scope);
    var t = _dragging ?? scope?.progress ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Auto-hidden only when there is genuinely no room — the sequencer's
        // gutter plus a track worth dragging in, beside the rail itself.
        //
        // The first cut gated this at 900px of *stage*, which is a different
        // box from the one the concept's media query meant: the motion list
        // takes 280 before this builder runs, and the shell takes its own
        // chrome before that, so the rail needed a window around 1400px and
        // simply never appeared. A number I have to guess is the wrong
        // mechanism, hence the toggle.
        var showRail = _showRail ?? (constraints.maxWidth >= 560);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: context.colors.bg,
                      child: _preview(context, session),
                    ),
                  ),
                  Divider(height: 1, color: context.colors.line),
                  _Transport(
                    scope: _scope,
                    value: _dragging,
                    onTransport: _transport,
                    railOpen: showRail,
                    onToggleRail: () => setState(() => _showRail = !showRail),
                  ),
                  Divider(height: 1, color: context.colors.line),
                  SizedBox(
                    height: 236,
                    child: MotionSequencer(
                      scope: scope,
                      problems: _writeProblems,
                      t: t,
                      selection: _selection,
                      // Picking a span *is* the request to see it. There is
                      // nothing else a selection does — the outline on the bar
                      // is feedback that the click landed, not a purpose — so
                      // a rail that stayed shut would make the gesture do
                      // nothing visible at all.
                      onSelect: (selection) => setState(() {
                        _selection = selection;
                        if (selection != null) _showRail = true;
                      }),
                      onSeek: _seek,
                      onSeekEnd: () => setState(() => _dragging = null),
                      onEdit: _edit,
                      onCreate: _create,
                    ),
                  ),
                ],
              ),
            ),
            if (showRail) ...[
              VerticalDivider(width: 1, color: context.colors.line),
              SizedBox(
                width: 264,
                child: MotionInspector(
                  scope: scope,
                  selection: _selection,
                  onEdit: _edit,
                  onDelete: _delete,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _preview(BuildContext context, CatalogSession? session) {
    var engine = session?.engine;
    if (session?.errorMessage case var error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.lg),
          child: Text(
            error,
            style: context.type.body.copyWith(color: context.colors.red),
          ),
        ),
      );
    }
    if (engine == null || engine.phase != EmbeddedEnginePhase.running) {
      return Center(
        child: Text(
          session?.busyWith ?? 'Starting the guest…',
          style: context.type.bodyMuted,
        ),
      );
    }
    var dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        var size = constraints.biggest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          engine.resize(
            (size.width * dpr).round(),
            (size.height * dpr).round(),
            dpr,
          );
        });
        return engine.textureId == null
            ? const SizedBox.expand()
            : Texture(textureId: engine.textureId!);
      },
    );
  }
}

/// Play, restart, and the clock.
///
/// **No slider.** The ruler scrubs across the sequencer's full width and every
/// collapsed group row scrubs with it, so a second control that could disagree
/// with the playhead is one control too many. Loop and speed are the two
/// affordances the concept has here that this does not, and both want a guest
/// verb that does not exist yet.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.scope,
    required this.value,
    required this.onTransport,
    required this.railOpen,
    required this.onToggleRail,
  });

  final Map<String, dynamic>? scope;
  final double? value;
  final ValueChanged<String> onTransport;
  final bool railOpen;
  final VoidCallback onToggleRail;

  @override
  Widget build(BuildContext context) {
    var playing = scope?['playing'] == true;
    var t = value ?? ((scope?['progress'] as num?)?.toDouble() ?? 0);
    var duration = (scope?['durationMs'] as num?)?.toInt() ?? 0;
    var ms = (t * duration).round();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: scope == null
                ? null
                : () => onTransport(playing ? 'pause' : 'play'),
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            tooltip: playing ? 'Pause' : 'Play',
          ),
          IconButton(
            onPressed: scope == null ? null : () => onTransport('restart'),
            icon: const Icon(Icons.replay),
            tooltip: 'Play from the start',
          ),
          const Spacer(),
          // Milliseconds, not a fraction: the values file is written in
          // milliseconds and this is the number you would type into it.
          SizedBox(
            width: 96,
            child: Text(
              scope == null ? '—' : '$ms / $duration ms',
              textAlign: TextAlign.right,
              style: context.type.caption.copyWith(
                color: context.colors.mut,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            onPressed: onToggleRail,
            icon: Icon(
              railOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            ),
            color: railOpen ? context.colors.accent : null,
            tooltip: railOpen ? 'Hide the inspector' : 'Show the inspector',
          ),
        ],
      ),
    );
  }
}
