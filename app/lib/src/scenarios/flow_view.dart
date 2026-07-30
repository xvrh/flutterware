import 'package:flutter/material.dart';

import '../catalog/devices.dart';
import '../plugins/native/scenarios_results.dart';
import '../ui/tappable.dart';
import '../ui/theme.dart';
import '../utils/graphite.dart';
import 'framed_shot.dart';

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
    required this.onOpenStep,
  });

  final List<ScenarioRunStep> steps;

  /// The device the run was framed as, or null for the bare surface.
  final CatalogDevice? device;

  /// A tap on a step — the caller pushes the detail page.
  final void Function(ScenarioRunStep) onOpenStep;

  @override
  State<ScenarioFlowView> createState() => _ScenarioFlowViewState();
}

class _ScenarioFlowViewState extends State<ScenarioFlowView> {
  // Opens zoomed out and a little inset, like dev_studio's run view did —
  // the first glance is the whole flow, not one giant phone.
  final _transform = TransformationController()
    ..value = ((Matrix4.identity() * 0.5 as Matrix4)
      ..translateByDouble(50.0, 100.0, 0, 1));

  var _scale = 0.5;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    var scale = _transform.value.getMaxScaleOnAxis();
    if (scale != _scale) setState(() => _scale = scale);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
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
    var inputs = [
      for (var (i, step) in steps.indexed)
        NodeInput(
          id: '${step.index}',
          next: [if (i + 1 < steps.length) '${steps[i + 1].index}'],
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
              transformationController: _transform,
              maxScale: 1.5,
              minScale: 0.05,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(5000),
              child: child,
            ),
            builder: (context, node) => _StepNode(
              byId[node.id]!,
              device: widget.device,
              onTap: () => widget.onOpenStep(byId[node.id]!),
            ),
            paintBuilder: (edge) => Paint()
              ..color = context.colors.mut3
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
          ),
        ),
        Positioned(
          right: FwSpacing.md,
          bottom: FwSpacing.md,
          child: _ZoomButtons(
            value: _scale,
            onScale: (factor) => _transform.value = _transform.value
                .scaledByDouble(factor, factor, factor, 1),
          ),
        ),
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode(this.step, {required this.device, required this.onTap});

  final ScenarioRunStep step;
  final CatalogDevice? device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            '${step.index} · ${step.name ?? 'step'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Sized to survive the canvas's zoom-out: at half scale this
            // reads like a caption.
            style: context.type.body.copyWith(
              fontSize: 22,
              color: context.colors.mut,
            ),
          ),
          const Gap(FwSpacing.md),
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              child: FramedShot(png: step.png, device: device),
            ),
          ),
        ],
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
