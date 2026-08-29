import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart' show StageKind;
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../previews/catalog_session.dart';
import '../../previews/compiler_daemon_client.dart';
import '../../embedder/embedded_engine.dart';
import '../../embedder/guest_texture.dart';
import '../../motion/discovery.dart';
import '../../motion/lane_model.dart';
import '../../motion/new_span.dart';
import '../../motion/stage_file.dart';
import '../../motion/values_file.dart';
import '../../ui/empty_state.dart';
import '../../ui/filter_bar.dart';
import '../../ui/loading_state.dart';
import '../../ui/tappable.dart';
import '../native_plugin.dart';
import 'motion_address.dart';
import 'motion_core.dart';
import 'motion_highlight.dart';
import 'motion_sequencer.dart';
import '../../ui/design/design.dart';
import '../../ui/error_state.dart';
import 'no_packages.dart';

export 'motion_core.dart' show MotionCore, motionPluginId;

/// The GUI half of the motion plugin: a band naming which motion you are on,
/// that motion running in a live guest, and a sequencer under it.
///
/// The panel owns no truth. The list comes from the core's syntactic scan,
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
    // Rebuilds when a scan lands: the core notifies, the plugin forwards.
    //
    // Every other native panel does this and this one did not, so it read the
    // core once and went cold — the scan finished, `notifyChanged` fired, and
    // nothing here was listening. It looked fine for as long as the scan beat
    // the first build; it stopped looking fine when the demo directory grew
    // enough for the panel to win that race, and then "Scanning for motions…"
    // stayed on screen until the panel was remounted by hand.
    //
    // Every read of the core belongs *inside* the builder, or the part left
    // outside is the part that stays stale.
    return AnimatedBuilder(
      animation: widget.plugin,
      builder: (context, _) {
        var place = _resolve();
        if (place == null) {
          return const NoPackagesConfigured(icon: Icons.movie_outlined);
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
      },
    );
  }

  Widget _body(
    BuildContext context,
    MotionPlace place,
    MotionScanResult? result,
    MotionRef? selected,
  ) {
    if (_core.errorFor(place.package) case var error?) {
      return ErrorState(title: 'The scan failed', message: '$error');
    }
    if (result == null) {
      return const LoadingState(title: 'Scanning for motions…');
    }
    if (result.motions.isEmpty) {
      return EmptyState(
        icon: Icons.movie_outlined,
        title: 'No motions here',
        message:
            'Nothing declares a MotionScope in '
            '${_core.directoryFor(place.package)}.',
      );
    }
    if (selected == null) {
      return const EmptyState(
        icon: Icons.timeline,
        title: 'Pick a motion',
        message: 'Opening one scrubs it.',
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
/// This replaces a 280px list down the left side. The shell's address bar
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
              size: FwIconSize.sm,
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
              size: FwIconSize.md,
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
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
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
/// you cannot see is one you cannot check.
class _ValuesFileBadge extends StatelessWidget {
  const _ValuesFileBadge(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    // Quiet, because it is a label and not a control. Painted in the accent —
    // soft fill, accent border, accent text — it was the most clickable-looking
    // thing on the panel and the only one with nothing behind it. That pairing
    // means *selected* everywhere else it is used, and a chip that is
    // permanently selected is just a chip that lies.
    return Tooltip(
      message: 'The only file this editor writes.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.sm,
          vertical: FwSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: context.colors.panel2,
          border: Border.all(color: context.colors.line),
          borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        ),
        child: Text(
          name,
          style: context.type.caption.copyWith(color: context.colors.mut),
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

  /// The draft stage as the file has it, or null where there is none.
  ///
  /// Two sources describe the same elements and they answer different
  /// questions: the guest says where a target *is* on screen, which is what a
  /// pointer hit-tests against, and this says what the file will be written
  /// back as. Neither can be derived from the other — a placeholder's `x` is
  /// not its extent, because the stage is centred in the guest.
  StageFile? _stage;

  /// Why the stage could not be read, if it could not. Shown rather than
  /// swallowed: an editor that silently stops offering to add things looks
  /// broken, and a refusal that names the offset is a fixable one.
  String? _stageProblem;

  /// What the file said last time, so a parse costs nothing on a poll that
  /// changed nothing. A person editing the stage by hand is expected, so this
  /// re-reads rather than trusting its own writes.
  DateTime? _stageStamp;

  /// The guest's own answer, or null before it has given one.
  Map<String, dynamic>? _scope;

  /// Where the panel says the playhead is, or null while the guest drives.
  ///
  /// The panel owns the playhead whenever the motion is not playing. The
  /// guest answers after the frame, so echoing it back would lag the finger;
  /// worse, releasing a drag used to hand ownership straight back, and a
  /// `MotionController` autoplays by default — so the guest's answer was
  /// "progress 1" and every scrub snapped to the end the moment you let go.
  ///
  /// Only a transport verb gives it back, because that is the only time the
  /// guest knows something about the playhead that the panel does not.
  double? _playhead;

  /// The newest position asked for, waiting for the socket.
  double? _wanted;

  var _seeking = false;

  /// Whether the playhead has been put somewhere deliberate yet.
  ///
  /// A motion autoplays on mount, so without this the panel opens on a screen
  /// that has already finished — the one frame of an animation that tells you
  /// least about it.
  var _parked = false;
  var _ticking = false;

  /// Why the last write was refused, or empty. Shown rather than swallowed: a
  /// drag that silently does nothing is worse than one that says why.
  List<MotionFileProblem> _writeProblems = const [];

  /// Which span the inspector is showing, as an address rather than a
  /// reference — the poll replaces the model underneath it every second.
  MotionSelection? _selection;

  /// Whether the inspector is up, once it has been set. Null means "whatever
  /// there is room for".
  bool? _showRail;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_MotionStage old) {
    super.didUpdateWidget(old);
    // The address carries the playhead, so navigating to the same motion at a
    // different `t` has to move it. Parking covers the first scope only, and
    // the stage's key is the package and file — a `t` that changed under an
    // unchanged key reached nothing at all before this.
    if (widget.place.t case var t? when t != old.place.t) {
      unawaited(_seek(t));
    }
  }

  void _start() {
    var core = widget.core;
    var package = widget.place.package;
    var session = CatalogSession(
      appPackageRoot: core.host.workspace.appContext.appToolDirectory.path,
      flutterSdkRoot: core.host.workspace.flutterSdk.root,
      projectRoot: p.join(core.host.worktree.path, package),
      worktreeRoot: core.host.worktree.path,
      // Same catalog as the previews panel, so the two share one daemon and
      // one warm kernel rather than compiling the same files twice.
      roots: core.host.catalogRootsFor(package),
      clock: core.host.projectClock,
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

  /// Names the scope this panel is showing in every guest call. The guest
  /// resolves a missing `scope` only while exactly one is mounted, so without
  /// this the lanes rendered on a two-scope app while every scrub, play and
  /// pause came back as a refusal.
  Map<String, String> get _scopeArgs => switch (_scope?['id']) {
    String id => {'scope': id},
    _ => const {},
  };

  /// Follows a playing motion, and asks nothing at all when none is.
  ///
  /// Idle, this costs one boolean read every 40ms. The alternative — ticking
  /// only while a transport is in flight — needs the panel to know when the
  /// motion *ended*, which is the thing it is asking about.
  Future<void> _followPlayhead() async {
    if (_ticking || _playhead != null) return;
    if (_scope == null || _scope!['playing'] != true) return;
    _ticking = true;
    try {
      var reply = await _session?.callGuestExtension(
        'ext.flutterware.motion.progress',
        args: _scopeArgs,
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
    _loadStage();
    var scopes = (listed?['scopes'] as List?)?.cast<Map<String, dynamic>>();
    setState(
      () => _scope = scopes == null || scopes.isEmpty ? null : scopes.first,
    );
    // The address decides where to open, and the start decides when it does
    // not — never wherever the autoplay happened to finish before anybody
    // looked. Once only, so a refresh mid-scrub does not drag you back.
    if (!_parked && _scope != null) {
      _parked = true;
      unawaited(_seek(widget.place.t ?? 0));
    }
  }

  /// Reads the stage file when it has changed, and not otherwise.
  ///
  /// Called off the same one-second poll as the lanes. The stat is what makes
  /// that free; the parse only runs on an edit, whoever made it.
  void _loadStage() {
    var path = widget.core.stagePathFor(
      widget.place.package,
      widget.motion.file,
    );
    var file = File(path);
    if (!file.existsSync()) {
      if (_stage != null || _stageProblem != null) {
        setState(() {
          _stage = null;
          _stageProblem = null;
          _stageStamp = null;
        });
      }
      return;
    }
    var stamp = file.lastModifiedSync();
    if (stamp == _stageStamp) return;
    _stageStamp = stamp;
    switch (parseStageFile(file.readAsStringSync())) {
      case StageFile stage:
        setState(() {
          _stage = stage;
          _stageProblem = null;
        });
      case StageParseFailure failure:
        setState(() {
          _stage = null;
          _stageProblem = '$failure';
        });
    }
  }

  /// Writes the stage back and asks for the reload that carries it — exactly
  /// what a lane edit does, and for the same reason: the disk is the model, but
  /// the daemon only sweeps for edits when somebody asks it to compile. Writing
  /// without this leaves a file on disk that nothing has read.
  Future<void> _writeStage(StageFile stage) async {
    widget.core.writeStage(widget.place.package, widget.motion.file, stage);
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _stageStamp = null;
    });
    await _session?.reloadIfChanged();
    await _refresh();
  }

  /// Puts a placeholder on the draft.
  ///
  /// No dialog and no name asked for: placing a rectangle should cost one
  /// click, and the name is a field on the element like any other. It lands
  /// below everything, which is the same rule `motion add-element` follows
  /// when nobody gives it a `y`.
  void _addElement(String kind) {
    var stage = _stage;
    if (stage == null) return;
    unawaited(
      _writeStage(
        stage.withElement(
          StageElementModel(
            target: MotionCore.freeTarget(stage, kind),
            kind: kind,
            x: 24,
            y: MotionCore.belowEverything(stage),
            width: kind == 'circle' ? 48 : (stage.width - 48).clamp(48, 320),
            height: kind == 'text' ? 28 : 48,
          ),
        ),
      ),
    );
  }

  /// Moves one element by a whole number of stage pixels.
  ///
  /// Rounded, because a drag samples in fractions of a logical pixel and the
  /// file is read by people — `x: 24` is a position, `x: 23.99999` is a
  /// smudge. Clamped to the stage, so a placeholder cannot be dragged off the
  /// only surface that shows it.
  void _moveElement(String target, Offset by) {
    var stage = _stage;
    if (stage == null) return;
    unawaited(
      _writeStage(
        StageFile(
          name: stage.name,
          width: stage.width,
          height: stage.height,
          background: stage.background,
          elements: [
            for (var element in stage.elements)
              if (element.target != target)
                element
              else
                StageElementModel(
                  target: element.target,
                  kind: element.kind,
                  x: (element.x + by.dx).roundToDouble().clamp(
                    0,
                    stage.width - element.width,
                  ),
                  y: (element.y + by.dy).roundToDouble().clamp(
                    0,
                    stage.height - element.height,
                  ),
                  width: element.width,
                  height: element.height,
                  label: element.label,
                  tint: element.tint,
                  radius: element.radius,
                ),
          ],
        ),
      ),
    );
  }

  /// One seek in flight, and the last one always lands.
  ///
  /// A drag samples far faster than a guest can draw, so intermediate positions
  /// are skipped — but *skipped*, not dropped: the newest wanted position is
  /// kept and sent as soon as the socket frees up. The previous guard simply
  /// returned while one was in flight, so the final position of a drag was
  /// never sent at all, and the playhead settled wherever the one sample that
  /// got through had left it.
  Future<void> _seek(double t) async {
    setState(() => _playhead = t);
    _wanted = t;
    if (_seeking) return;
    _seeking = true;
    try {
      while (true) {
        var wanted = _wanted;
        if (wanted == null) break;
        _wanted = null;
        await _session?.callGuestExtension(
          'ext.flutterware.motion.seek',
          args: {..._scopeArgs, 't': '$wanted'},
        );
        if (!mounted) return;
      }
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

    var atMs = ((_playhead ?? scope!.progress) * scope!.durationMs).round();
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

  /// Flips which body the guest builds — the draft stage or the real screen.
  ///
  /// A guest verb rather than a rebuild of anything here: the two bodies live
  /// in one `MotionScope`, so the playhead, the lanes and the selection are all
  /// the same objects on the other side of the flip. Refreshing after it is
  /// what redraws the lanes, since a target that only the draft names appears
  /// and disappears with the host.
  Future<void> _setHost(MotionHostView host) async {
    await _session?.callGuestExtension(
      'ext.flutterware.motion.host',
      args: {..._scopeArgs, 'host': host.wire},
    );
    await _refresh();
  }

  Future<void> _transport(String verb) async {
    // Play and restart hand the playhead back; pause leaves it where it is, and
    // the panel goes on owning it so the next scrub has something to start from.
    if (verb != 'pause') setState(() => _playhead = null);
    await _session?.callGuestExtension(
      'ext.flutterware.motion.transport',
      args: {..._scopeArgs, 'verb': verb},
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
    var t = _playhead ?? scope?.progress ?? 0;

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
                      child: _preview(
                        context,
                        session,
                        scope,
                        // Only what is selected. Ringing every target at once
                        // would be a screen of rectangles and no answer to the
                        // question the ring is for — which one is this lane?
                        _selection == null
                            ? null
                            : scope?.target(_selection!.target),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: context.colors.line),
                  _Transport(
                    scope: _scope,
                    value: _playhead,
                    onTransport: _transport,
                    host: scope?.host ?? MotionHostView.real,
                    hosts: scope?.hosts ?? const [],
                    onHost: _setHost,
                    // Only on the draft, and only where there is a stage file
                    // to write. The real screen's targets are named in a build
                    // method, and the tool may not touch one.
                    onAdd: _stage != null && scope?.host == MotionHostView.draft
                        ? _addElement
                        : null,
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

  Widget _preview(
    BuildContext context,
    CatalogSession? session,
    MotionScopeView? scope,
    MotionTargetView? highlight,
  ) {
    var engine = session?.engine;
    if (session?.errorMessage case var error?) {
      return ErrorState(title: 'The guest could not start', message: error);
    }
    if (engine == null || engine.phase != EmbeddedEnginePhase.running) {
      return LoadingState(
        title: 'Starting the guest…',
        // `busyWith` is a fragment by design — the rail renders it as
        // "Motion · building" — so it belongs on the second line. On its own
        // it put the single lowercase word `building` in the middle of the
        // stage, with no spinner and no sentence around it.
        message: session?.busyWith,
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
        if (engine.textureId == null) return const SizedBox.expand();
        // Only what is on the draft can be dragged, and only while the draft is
        // what is being shown. A target the real screen lays out has no `x` to
        // write — moving it would mean editing somebody's build method.
        var stage = _stage;
        return Stack(
          fit: StackFit.expand,
          children: [
            GuestTexture(textureId: engine.textureId!),
            MotionStageHighlight(
              extent: highlight?.extent,
              label: highlight?.name,
            ),
            if (stage != null && scope?.host == MotionHostView.draft)
              _DraftDrag(stage: stage, guest: size, onMoved: _moveElement),
          ],
        );
      },
    );
  }
}

/// Dragging a placeholder around the draft.
///
/// The rects come from the stage file, not from the guest's reported extents,
/// and the difference is not an optimisation. An extent is where a target has
/// been *moved to* — that is the whole point of it, so a ring follows an
/// animation — and the file holds where it was laid out. Dragging the moved box
/// and writing the laid-out one puts the element somewhere neither of them was.
/// The layout rect is also there before the guest has said anything, which is
/// what makes a freshly added placeholder draggable straight away.
///
/// The one thing this has to know about the guest is that [MotionStageView]
/// centres the stage in it, which is a translation and nothing else.
class _DraftDrag extends StatefulWidget {
  const _DraftDrag({
    required this.stage,
    required this.guest,
    required this.onMoved,
  });

  final StageFile stage;

  /// The guest's logical size, which is this layer's box — the panel is what
  /// sized both.
  final Size guest;

  final void Function(String target, Offset by) onMoved;

  @override
  State<_DraftDrag> createState() => _DraftDragState();
}

class _DraftDragState extends State<_DraftDrag> {
  String? _target;
  Offset _by = Offset.zero;

  /// Where the stage's own origin sits in this box.
  Offset get _origin => Offset(
    (widget.guest.width - widget.stage.width) / 2,
    (widget.guest.height - widget.stage.height) / 2,
  );

  Rect _rectOf(StageElementModel element) => Rect.fromLTWH(
    element.x + _origin.dx,
    element.y + _origin.dy,
    element.width,
    element.height,
  );

  /// Topmost first, because a later element paints over an earlier one and the
  /// thing you can see is the thing you meant to grab.
  StageElementModel? _hit(Offset at) {
    for (var element in widget.stage.elements.reversed) {
      if (_rectOf(element).contains(at)) return element;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    var target = _target;
    var element = target == null
        ? null
        : widget.stage.elements.firstWhereOrNull((e) => e.target == target);
    var ghost = element == null ? null : _rectOf(element).shift(_by);

    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) {
          var hit = _hit(details.localPosition);
          if (hit == null) return;
          setState(() {
            _target = hit.target;
            _by = Offset.zero;
          });
        },
        onPanUpdate: (details) {
          if (_target == null) return;
          setState(() => _by += details.delta);
        },
        onPanEnd: (_) {
          var moved = _target;
          if (moved == null) return;
          // The write lands in `_stage` synchronously, so the ring is already
          // at the new position when this clears — the texture catches up a
          // beat later, which reads as the thing moving rather than as a snap
          // back to where it was.
          if (_by != Offset.zero) widget.onMoved(moved, _by);
          setState(() {
            _target = null;
            _by = Offset.zero;
          });
        },
        child: ghost == null
            ? const SizedBox.expand()
            : MotionStageHighlight(extent: ghost, label: target),
      ),
    );
  }
}

/// The one thing that creates a target.
///
/// A menu of kinds rather than a form, because the name is not a decision to
/// make before the rectangle exists — it is a field on the element, changed
/// where the rest of it is. The kinds are the stage's own vocabulary, so this
/// list is complete by construction rather than by remembering to update it.
class _AddElement extends StatelessWidget {
  const _AddElement({required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (var kind in StageKind.values)
          MenuItemButton(
            onPressed: () => onAdd(kind.name),
            child: Text(switch (kind) {
              StageKind.box => 'Box',
              StageKind.text => 'Text',
              StageKind.circle => 'Circle',
            }, style: context.type.body),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add_box_outlined),
        tooltip: 'Add a placeholder to the draft',
      ),
    );
  }
}

/// Play, restart, and the clock.
///
/// No slider. The ruler scrubs across the sequencer's full width and every
/// collapsed group row scrubs with it, so a second control that could disagree
/// with the playhead is one control too many. Loop and speed are the two
/// affordances the concept has here that this does not, and both want a guest
/// verb that does not exist yet.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.scope,
    required this.value,
    required this.onTransport,
    required this.host,
    required this.hosts,
    required this.onHost,
    required this.onAdd,
    required this.railOpen,
    required this.onToggleRail,
  });

  final Map<String, dynamic>? scope;
  final double? value;
  final ValueChanged<String> onTransport;
  final MotionHostView host;
  final List<MotionHostView> hosts;
  final ValueChanged<MotionHostView> onHost;

  /// Adds a placeholder of that kind, or null where nothing can be added.
  final ValueChanged<String>? onAdd;

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
          const Gap(FwSpacing.sm),
          // Draft or real, and only where there are both. A motion with one
          // body would get a control whose every use is a refusal, and a
          // control that cannot be used still has to be read.
          if (hosts.length > 1)
            for (var candidate in hosts) ...[
              FwPill(
                label: candidate.label,
                selected: candidate == host,
                onTap: () => onHost(candidate),
              ),
              const Gap(FwSpacing.xs),
            ],
          if (onAdd case var add?) ...[
            const Gap(FwSpacing.xs),
            _AddElement(onAdd: add),
          ],
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
