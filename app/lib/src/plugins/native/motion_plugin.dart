import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../address/address_scope.dart';
import '../../catalog/catalog_session.dart';
import '../../catalog/compiler_daemon_client.dart';
import '../../embedder/embedded_engine.dart';
import '../../motion/discovery.dart';
import '../../ui/design/spacing.dart';
import '../../ui/design/tokens.dart';
import '../../ui/tappable.dart';
import '../native_plugin.dart';
import 'motion_address.dart';
import 'motion_core.dart';

export 'motion_core.dart' show MotionCore, motionPluginId;

/// The GUI half of the motion plugin: the motions a package declares on the
/// left, and the selected one running in a live guest with a playhead under it.
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: _MotionList(
            core: _core,
            place: place,
            result: result,
            selected: selected,
          ),
        ),
        VerticalDivider(width: 1, color: context.colors.line),
        Expanded(
          child: selected == null
              ? Center(
                  child: Text(
                    result == null
                        ? 'Scanning…'
                        : 'Select a motion to scrub it.',
                    style: context.type.bodyMuted,
                  ),
                )
              : _MotionStage(
                  key: ValueKey('${place.package}/${selected.file}'),
                  core: _core,
                  place: place,
                  motion: selected,
                ),
        ),
      ],
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

class _MotionList extends StatelessWidget {
  const _MotionList({
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
    if (core.errorFor(place.package) case var error?) {
      return Padding(
        padding: const EdgeInsets.all(FwSpacing.md),
        child: Text(
          '$error',
          style: context.type.body.copyWith(color: context.colors.red),
        ),
      );
    }
    var result = this.result;
    if (result == null) {
      return Center(child: Text('Scanning…', style: context.type.bodyMuted));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.sm),
      children: [
        if (result.motions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(FwSpacing.md),
            child: Text(
              'No MotionScope found in '
              '${core.directoryFor(place.package)}.',
              style: context.type.bodyMuted,
            ),
          ),
        for (var motion in result.motions)
          Tappable(
            onTap: () => AddressScope.of(context).go(
              core.addressFor(
                place.package,
                file: motion.file,
                motion: motion.values,
                t: place.t,
              ),
            ),
            child: Container(
              color: identical(motion, selected)
                  ? context.colors.accentSoft
                  : null,
              padding: const EdgeInsets.symmetric(
                horizontal: FwSpacing.md,
                vertical: FwSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    motion.values ?? '<expression>',
                    style: context.type.body,
                  ),
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
          ),
        // Never presented as an aside: a target named by an expression is
        // invisible to the scan and perfectly real at run time, so a list that
        // showed only what it could parse would read as complete and be wrong.
        for (var diagnostic in result.diagnostics)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.md,
              vertical: FwSpacing.xs,
            ),
            child: Text(
              diagnostic,
              style: context.type.caption.copyWith(color: context.colors.amber),
            ),
          ),
      ],
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
    return Column(
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
          onSeek: _seek,
          onSeekEnd: () => setState(() => _dragging = null),
          onTransport: _transport,
        ),
        Divider(height: 1, color: context.colors.line),
        SizedBox(height: 220, child: _Lanes(scope: _scope)),
      ],
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

class _Transport extends StatelessWidget {
  const _Transport({
    required this.scope,
    required this.value,
    required this.onSeek,
    required this.onSeekEnd,
    required this.onTransport,
  });

  final Map<String, dynamic>? scope;
  final double? value;
  final ValueChanged<double> onSeek;
  final VoidCallback onSeekEnd;
  final ValueChanged<String> onTransport;

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
          Expanded(
            child: Slider(
              value: t.clamp(0.0, 1.0),
              onChanged: scope == null ? null : onSeek,
              onChangeEnd: (_) => onSeekEnd(),
            ),
          ),
          // Milliseconds, not a fraction: the values file is written in
          // milliseconds and this is the number you would type into it.
          SizedBox(
            width: 76,
            child: Text(
              scope == null ? '—' : '$ms / $duration',
              textAlign: TextAlign.right,
              style: context.type.caption.copyWith(
                color: context.colors.mut,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gutter: one group per target, one row per property, read-only for now.
class _Lanes extends StatelessWidget {
  const _Lanes({required this.scope});

  final Map<String, dynamic>? scope;

  @override
  Widget build(BuildContext context) {
    var scope = this.scope;
    if (scope == null) {
      return Center(
        child: Text(
          'No motion mounted in the guest yet.',
          style: context.type.bodyMuted,
        ),
      );
    }
    var targets = (scope['targets'] as List).cast<Map<String, dynamic>>();
    var duration = (scope['durationMs'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: FwSpacing.sm),
      children: [
        for (var target in targets) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.md,
              FwSpacing.sm,
              FwSpacing.md,
              FwSpacing.xs,
            ),
            child: Row(
              spacing: FwSpacing.sm,
              children: [
                Text('${target['name']}', style: context.type.body),
                if (target['named'] != true)
                  _Chip(
                    'never named',
                    tone: context.colors.amber,
                    hint: 'Tuned, but no build asked for it — prunable.',
                  ),
                if ((target['offered'] as List).isNotEmpty)
                  _Chip(
                    '+${(target['offered'] as List).length}',
                    tone: context.colors.mut,
                    hint: 'Available through a MotionBox, not tuned.',
                  ),
              ],
            ),
          ),
          for (var property
              in (target['properties'] as List).cast<Map<String, dynamic>>())
            _Lane(property: property, duration: duration),
        ],
      ],
    );
  }
}

class _Lane extends StatelessWidget {
  const _Lane({required this.property, required this.duration});

  final Map<String, dynamic> property;
  final int duration;

  @override
  Widget build(BuildContext context) {
    // The state is the guest's answer, not a re-derivation. `offered` counts as
    // wiring for a tuned property and does not create a lane for an untuned
    // one, and getting that wrong once was enough.
    var (tone, hint) = switch (property['state']) {
      'dead' => (context.colors.amber, 'Tuned, and nothing reads it.'),
      'untuned' => (context.colors.mut2, 'Read, and nothing tunes it yet.'),
      _ => (context.colors.accent, 'Tuned and applied.'),
    };
    var segments = (property['segments'] as List).cast<Map<String, dynamic>>();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: 1,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              '${property['name']}',
              style: context.type.caption.copyWith(color: context.colors.mut),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: hint,
              child: SizedBox(
                height: 14,
                child: CustomPaint(
                  painter: _SpanPainter(
                    segments: segments,
                    duration: duration,
                    tone: tone,
                    dashed: property['state'] == 'untuned',
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              _valueLabel(property['value']),
              textAlign: TextAlign.right,
              style: context.type.caption.copyWith(
                color: context.colors.mut,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _valueLabel(Object? value) => switch (value) {
    num() => value.toStringAsFixed(2),
    {'color': int color} =>
      '#${color.toRadixString(16).padLeft(8, '0').toUpperCase()}',
    _ => '—',
  };
}

class _SpanPainter extends CustomPainter {
  _SpanPainter({
    required this.segments,
    required this.duration,
    required this.tone,
    required this.dashed,
  });

  final List<Map<String, dynamic>> segments;
  final int duration;
  final Color tone;

  /// A property nothing tunes has no span to draw, so the lane is the outline
  /// of where one would go — which is the whole of the creation path.
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()..color = tone;
    if (segments.isEmpty || duration <= 0) {
      if (!dashed) return;
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(
          Offset(x, size.height / 2),
          Offset((x + 3).clamp(0.0, size.width), size.height / 2),
          paint,
        );
      }
      return;
    }
    for (var segment in segments) {
      var start = ((segment['startMs'] as num) / duration) * size.width;
      var end = ((segment['endMs'] as num) / duration) * size.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          // A step keyframe is a zero-length span, and a zero-width rect draws
          // nothing at all — so it gets the minimum width that reads as a mark.
          Rect.fromLTRB(start, 3, (end - start) < 2 ? start + 2 : end, 11),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpanPainter old) =>
      old.duration != duration ||
      old.tone != tone ||
      old.dashed != dashed ||
      old.segments.length != segments.length;
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.tone, required this.hint});

  final String label;
  final Color tone;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: tone.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: context.type.caption.copyWith(color: tone)),
      ),
    );
  }
}
