import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../previews/devices.dart';
import '../plugins/native/scenarios_results.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import '../utils/graphite.dart';
import 'artifacts.dart';
import 'framed_shot.dart';
import 'motion_player.dart';
import 'step_status.dart';

/// One run as a flow: every captured step a device-framed screenshot on a
/// pannable, zoomable canvas — dev_studio's proven shape, on the design
/// tokens.
///
/// Laid out by graphite even though today's runs are linear chains: splits
/// fan a scenario into a DAG, and when they arrive the canvas is already the
/// right kind of surface.
class ScenarioFlowView extends StatefulWidget {
  const ScenarioFlowView({
    super.key,
    required this.steps,
    required this.device,
    required this.transform,
    required this.onOpenStep,
    this.statusFallback = Brightness.dark,
  });

  final List<ScenarioRunStep> steps;

  /// The device the run was framed as, or null for the bare surface.
  final Device? device;

  /// Status-chrome tint when a step declared no overlay style.
  final Brightness statusFallback;

  /// Owned by the page, not this widget, so pushing a step's detail and
  /// coming back lands exactly where the canvas was.
  final TransformationController transform;

  /// A tap on a step — the caller pushes the detail page.
  final void Function(ScenarioRunStep) onOpenStep;

  /// The transform a fresh page starts from: zoomed out and a little inset,
  /// like dev_studio's run view — the first glance is the whole flow, not
  /// one giant phone.
  static Matrix4 initialTransform() =>
      (Matrix4.identity() * 0.5 as Matrix4)
        ..translateByDouble(50.0, 100.0, 0, 1);

  @override
  State<ScenarioFlowView> createState() => _ScenarioFlowViewState();
}

class _ScenarioFlowViewState extends State<ScenarioFlowView> {
  late var _scale = widget.transform.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_onTransform);
    // For ⌘-scroll zoom: the modifier state decides what a trackpad scroll
    // means, and only key events say when it changed.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    setState(() {});
    return false;
  }

  bool get _zoomKeyPressed =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  void _onTransform() {
    var scale = widget.transform.value.getMaxScaleOnAxis();
    if (scale != _scale) setState(() => _scale = scale);
  }

  @override
  void didUpdateWidget(ScenarioFlowView old) {
    super.didUpdateWidget(old);
    if (old.transform != widget.transform) {
      old.transform.removeListener(_onTransform);
      widget.transform.addListener(_onTransform);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.transform.removeListener(_onTransform);
    super.dispose();
  }

  Size get _cell {
    var device = widget.device;
    // Room for the label above and the frame's bezels around the screen.
    if (device == null) return const Size(800 + 60, 600 + 100);
    return Size(device.width + 120, device.height + 180);
  }

  @override
  Widget build(BuildContext context) {
    var steps = widget.steps;
    // The edges are the parent links the capture recorded — a linear
    // scenario chains, a split fans out. Data without parents (older
    // artifacts) falls back to the chain the list order implies.
    var hasParents = steps.any((s) => s.parent != null);
    var children = <int, List<int>>{};
    if (hasParents) {
      for (var step in steps) {
        if (step.parent case var parent?) {
          children.putIfAbsent(parent, () => []).add(step.index);
        }
      }
    } else {
      for (var (i, step) in steps.indexed) {
        if (i + 1 < steps.length) children[step.index] = [steps[i + 1].index];
      }
    }
    var inputs = [
      for (var step in steps)
        NodeInput(
          id: '${step.index}',
          next: [
            for (var child in children[step.index] ?? const <int>[]) '$child',
          ],
        ),
    ];
    var byId = {for (var step in steps) '${step.index}': step};

    return Stack(
      children: [
        Positioned.fill(
          child: DirectGraph(
            list: inputs,
            cellSize: _cell,
            cellPadding: 90,
            contactEdgesDistance: 0,
            tipLength: 20,
            orientation: MatrixOrientation.horizontal,
            interactiveBuilder: (context, child) => InteractiveViewer(
              transformationController: widget.transform,
              maxScale: 1.5,
              minScale: 0.05,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(5000),
              // A mouse wheel zooms by itself; a trackpad scroll pans unless
              // ⌘ (or Ctrl) turns it into the zoom gesture — dev_studio's
              // behaviour.
              trackpadScrollCausesScale: _zoomKeyPressed,
              child: child,
            ),
            builder: (context, node) => _StepNode(
              byId[node.id]!,
              device: widget.device,
              statusFallback: widget.statusFallback,
              onTap: () => widget.onOpenStep(byId[node.id]!),
            ),
            paintBuilder: (edge) => Paint()
              ..color = context.colors.mut3
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
            // What the arrow has to say, in two registers. The split's branch
            // label goes on the arrow that forks — dev_studio's placement, and
            // the one that reads: a fan-out is several arrows leaving one
            // node, and the question is which arrow is which. Under it, the
            // transition itself: the verb that caused the next frame and how
            // many events the app fired getting there, so the flow reads as
            // `tap "Pay" › 4 events › Receipt` rather than as two pictures.
            edgeTooltip: (from, to) {
              var step = byId[to];
              if (step == null) return null;
              var transition = scenarioStepTransition(step);
              // Spelled out on its own line rather than iconified: the gap
              // between two nodes is narrow, a glyph there reads as an
              // artifact, and `7 events` needs no legend.
              var count = step.notableEventCount;
              var events = count == 0
                  ? ''
                  : '\n$count event${count == 1 ? '' : 's'}';
              // How long the app took to get here, in its own milliseconds —
              // only where the run recorded the motion, which makes it the
              // cue that hovering the node will play it. Fake time, so it is
              // the animation's declared duration and never a measurement of
              // this machine.
              var motion = step.hasMotion
                  ? '${events.isEmpty ? '\n' : ' · '}'
                        '${scenarioMotionDuration(step).inMilliseconds}ms'
                  : '';
              if (step.branch == null && transition == null) return null;
              return EdgeTooltip(
                step.branch,
                // Sized like the node labels, for the same reason: the canvas
                // opens at half scale.
                style: context.type.body.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: context.colors.accent,
                ),
                subtitle: transition == null
                    ? null
                    : '$transition$events$motion',
                subtitleStyle: context.type.body.copyWith(
                  fontSize: 18,
                  color: context.colors.mut,
                ),
              );
            },
          ),
        ),
        Positioned(
          right: FwSpacing.md,
          bottom: FwSpacing.md,
          child: _ZoomButtons(
            value: _scale,
            onScale: (factor) => widget.transform.value = widget.transform.value
                .scaledByDouble(factor, factor, factor, 1),
          ),
        ),
      ],
    );
  }
}

/// One step on the canvas — and, when the run recorded it, the transition
/// that arrived at it.
///
/// **Playing the arrow means playing the node.** The frames end on the very
/// screenshot the node is already showing, so a pointer entering the node
/// rewinds it and lets it run forward into the picture that was there all
/// along: no popover, no player chrome, no layout moving on a canvas that is
/// already a dense wall of phones. Leaving parks it back on the still.
class _StepNode extends StatefulWidget {
  const _StepNode(
    this.step, {
    required this.device,
    required this.statusFallback,
    required this.onTap,
  });

  final ScenarioRunStep step;
  final Device? device;
  final Brightness statusFallback;
  final VoidCallback onTap;

  @override
  State<_StepNode> createState() => _StepNodeState();
}

class _StepNodeState extends State<_StepNode>
    with SingleTickerProviderStateMixin {
  ScenarioMotionController? _motion;

  @override
  void didUpdateWidget(_StepNode old) {
    super.didUpdateWidget(old);
    // A re-run replaces the step under this node; whatever was playing was
    // the previous run's frames, and its files are already deleted — so the
    // decoded pixels behind them are dead weight and go back now.
    if (old.step.frames != widget.step.frames) {
      _disposePlayer();
      scenarioMotionResidency.forget(old.step);
    }
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  void _disposePlayer() {
    _motion?.dispose();
    _motion = null;
  }

  void _enter() {
    if (!widget.step.hasMotion) return;
    var motion = _motion ??= ScenarioMotionController.forStep(
      widget.step,
      this,
    )!..addListener(_onFrame);
    // Warmed rather than played-into: the first pass over a recording is the
    // only one that decodes, and the pointer arriving is the earliest honest
    // moment to pay for it.
    unawaited(precacheScenarioMotion(context, widget.step));
    motion.play();
  }

  void _exit() => _motion?.rest();

  void _onFrame() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var step = widget.step;
    var motion = _motion;
    var frame = motion == null || !motion.playing
        ? null
        : scenarioFrameImage(
            ScenarioArtifactsScope.of(context),
            step,
            motion.frames[motion.index],
          );

    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Tappable(
        onTap: widget.onTap,
        child: Column(
          children: [
            Text(
              '${step.index} · ${scenarioStepLabel(step)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Sized to survive the canvas's zoom-out: at half scale this
              // reads like a caption.
              style: context.type.body.copyWith(
                fontSize: 22,
                color: scenarioStepTone(context, step),
              ),
            ),
            const Gap(FwSpacing.md),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                child: FramedShot(
                  step: step,
                  device: widget.device,
                  fallbackBrightness: widget.statusFallback,
                  image: frame,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// dev_studio's zoom control, on the tokens.
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.value, required this.onScale});

  final double value;
  final void Function(double factor) onScale;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(context.radii.radius),
        border: Border.all(color: colors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(context, Icons.zoom_out, () => onScale(0.9)),
          Text('${(value * 100).round()}%', style: context.type.caption),
          _button(context, Icons.zoom_in, () => onScale(1.1)),
        ],
      ),
    );
  }

  Widget _button(BuildContext context, IconData icon, VoidCallback onTap) {
    return Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.sm),
        child: Icon(icon, size: 18, color: context.colors.mut),
      ),
    );
  }
}
