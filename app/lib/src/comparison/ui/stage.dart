import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/tappable.dart';
import '../../ui/theme.dart';
import '../pixel_diff.dart';
import 'shot_image.dart';

/// The five ways of looking at two frames.
///
/// **Five, because each answers a question the others cannot.** Side by side
/// says what each one *is*; the slider says where a boundary falls; onion says
/// how far something moved; blink is the only one that finds a two-pixel shift
/// a human eye would otherwise walk past; pixels says where to look without
/// needing an eye at all — and it is the one an agent reads.
enum StageMode {
  sideBySide('side by side'),
  slider('slider'),
  onion('onion'),
  blink('blink'),
  pixels('pixels');

  const StageMode(this.label);

  final String label;
}

Key stageModeKey(StageMode mode) => ValueKey('stage.mode.${mode.name}');

const stageKey = Key('comparison-stage');

/// Two frames in one place, five ways.
class ComparisonStage extends StatefulWidget {
  const ComparisonStage({
    super.key,
    required this.shots,
    required this.mode,
    required this.onMode,
    this.diff,
  });

  final ShotPair shots;
  final StageMode mode;
  final ValueChanged<StageMode> onMode;

  /// Where the pixels moved, for the clusters overlay.
  final PixelDiff? diff;

  @override
  State<ComparisonStage> createState() => _ComparisonStageState();
}

class _ComparisonStageState extends State<ComparisonStage> {
  /// Where the slider's boundary sits, 0 (all base) to 1 (all head).
  var _split = 0.5;

  /// How much of head shows through in onion mode.
  var _blend = 0.5;

  /// Which side blink is showing.
  var _blinkHead = true;
  Timer? _blink;

  @override
  void initState() {
    super.initState();
    _syncBlink();
  }

  @override
  void didUpdateWidget(ComparisonStage old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _syncBlink();
  }

  /// **Only while blink is showing.** A timer left running behind another mode
  /// rebuilds the whole detail pane twice a second for nothing, which on a
  /// panel that also holds a live list is the kind of cost nobody attributes to
  /// the thing that caused it.
  void _syncBlink() {
    _blink?.cancel();
    _blink = null;
    if (widget.mode != StageMode.blink) return;
    _blink = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) setState(() => _blinkHead = !_blinkHead);
    });
  }

  @override
  Widget build(BuildContext context) {
    var shots = widget.shots;
    var base = shots.base;
    var head = shots.head;

    return Column(
      key: stageKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeBar(
          mode: widget.mode,
          onMode: widget.onMode,
          // A mode that needs two frames is not offered when there is one:
          // sliding against nothing is a control that does something and
          // means nothing.
          enabled: base != null && head != null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(FwSpacing.xl),
            child: base == null || head == null
                ? _OneSided(base: base, head: head)
                : _Body(
                    mode: widget.mode,
                    base: base,
                    head: head,
                    diff: widget.diff,
                    split: _split,
                    blend: _blend,
                    blinkHead: _blinkHead,
                  ),
          ),
        ),
        if (base != null && head != null)
          _Controls(
            mode: widget.mode,
            split: _split,
            blend: _blend,
            onSplit: (value) => setState(() => _split = value),
            onBlend: (value) => setState(() => _blend = value),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _blink?.cancel();
    super.dispose();
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.mode,
    required this.base,
    required this.head,
    required this.split,
    required this.blend,
    required this.blinkHead,
    this.diff,
  });

  final StageMode mode;
  final Shot base;
  final Shot head;
  final PixelDiff? diff;
  final double split;
  final double blend;
  final bool blinkHead;

  @override
  Widget build(BuildContext context) => switch (mode) {
    StageMode.sideBySide => Row(
      children: [
        Expanded(
          child: _Framed(label: 'base', child: ShotView(base)),
        ),
        const Gap(FwSpacing.xl),
        Expanded(
          child: _Framed(label: 'head', child: ShotView(head)),
        ),
      ],
    ),
    StageMode.slider => _Framed(
      label: 'base · head',
      child: _Stacked(
        base: base,
        head: head,
        // **Clipped, not cross-faded.** A slider is for reading where a
        // boundary falls — a button's edge, a baseline — and a soft one is
        // exactly the thing you cannot measure against.
        clip: split,
      ),
    ),
    StageMode.onion => _Framed(
      label: 'base under head',
      child: _Stacked(base: base, head: head, opacity: blend),
    ),
    StageMode.blink => _Framed(
      label: blinkHead ? 'head' : 'base',
      child: ShotView(blinkHead ? head : base),
    ),
    StageMode.pixels => _Framed(
      label: diff == null
          ? 'head'
          : '${(diff!.fraction * 100).toStringAsFixed(2)}% moved, '
                '${diff!.clusters.length} region'
                '${diff!.clusters.length == 1 ? '' : 's'}',
      child: _Clusters(head: head, diff: diff),
    ),
  };
}

/// Two frames on one rect, one clipped or faded over the other.
class _Stacked extends StatelessWidget {
  const _Stacked({
    required this.base,
    required this.head,
    this.clip,
    this.opacity = 1.0,
  });

  final Shot base;
  final Shot head;

  /// Fraction of the width the head frame occupies, from the left.
  final double? clip;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Both frames laid on the *base* aspect, so a head that changed size
        // shows that change as a change rather than as a different framing.
        var box = _fit(base.aspect, constraints.biggest);
        return Center(
          child: SizedBox(
            width: box.width,
            height: box.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ShotView(base),
                if (clip == null)
                  ShotView(head, opacity: opacity)
                else ...[
                  ClipRect(
                    clipper: _LeftFraction(clip!),
                    child: ShotView(head),
                  ),
                  Positioned(
                    left: box.width * clip! - 1,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: ColoredBox(color: colors.accent),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LeftFraction extends CustomClipper<Rect> {
  const _LeftFraction(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftFraction old) => old.fraction != fraction;
}

/// The head frame with the changed regions boxed on it.
///
/// **Boxes on the picture rather than a heat map.** A reader wants to know
/// where to look, and the answer has to stay legible against whatever the
/// preview happens to be — an overlay that tints changed pixels disappears on
/// a dark screen and swamps a light one.
class _Clusters extends StatelessWidget {
  const _Clusters({required this.head, this.diff});

  final Shot head;
  final PixelDiff? diff;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        var box = _fit(head.aspect, constraints.biggest);
        return Center(
          child: SizedBox(
            width: box.width,
            height: box.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ShotView(head),
                if (diff case var diff?)
                  CustomPaint(
                    painter: _ClusterPainter(diff: diff, color: colors.amber),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClusterPainter extends CustomPainter {
  const _ClusterPainter({required this.diff, required this.color});

  final PixelDiff diff;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (diff.width == 0 || diff.height == 0) return;
    var scaleX = size.width / diff.width;
    var scaleY = size.height / diff.height;
    var stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    var fill = Paint()..color = color.withValues(alpha: 0.16);
    for (var rect in diff.clusters) {
      // Grown by a pixel so a one-pixel cluster is a box you can see rather
      // than a line you cannot.
      var box = Rect.fromLTWH(
        rect.x * scaleX - 1,
        rect.y * scaleY - 1,
        rect.width * scaleX + 2,
        rect.height * scaleY + 2,
      );
      canvas
        ..drawRect(box, fill)
        ..drawRect(box, stroke);
    }
  }

  @override
  bool shouldRepaint(_ClusterPainter old) =>
      old.diff != diff || old.color != color;
}

/// One frame, when only one side has one.
class _OneSided extends StatelessWidget {
  const _OneSided({this.base, this.head});

  final Shot? base;
  final Shot? head;

  @override
  Widget build(BuildContext context) {
    var only = head ?? base;
    if (only == null) {
      return Center(
        child: Text(
          'Neither side rendered.',
          style: context.type.body.copyWith(color: context.colors.mut),
        ),
      );
    }
    return _Framed(
      label: head != null ? 'head only' : 'base only',
      child: ShotView(only),
    );
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.micro.copyWith(color: colors.mut)),
        const Gap(FwSpacing.xs),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.line),
              color: colors.panel,
            ),
            child: Padding(
              padding: const EdgeInsets.all(FwSpacing.sm),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.mode,
    required this.onMode,
    required this.enabled,
  });

  final StageMode mode;
  final ValueChanged<StageMode> onMode;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.xl,
        vertical: FwSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          for (var option in StageMode.values)
            Padding(
              padding: const EdgeInsets.only(right: FwSpacing.xs),
              child: Tappable.builder(
                key: stageModeKey(option),
                onTap: enabled && option != mode ? () => onMode(option) : null,
                builder: (context, hovered) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.md,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: option == mode
                        ? colors.accent.withValues(alpha: 0.12)
                        : hovered && enabled
                        ? colors.hoverOverlay
                        : null,
                    borderRadius: BorderRadius.circular(
                      context.radii.radiusSmall,
                    ),
                  ),
                  child: Text(
                    option.label,
                    style: context.type.micro.copyWith(
                      color: option == mode
                          ? colors.accent
                          : enabled
                          ? colors.mut
                          : colors.mut3,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The one slider the current mode has, and nothing when it has none.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.mode,
    required this.split,
    required this.blend,
    required this.onSplit,
    required this.onBlend,
  });

  final StageMode mode;
  final double split;
  final double blend;
  final ValueChanged<double> onSplit;
  final ValueChanged<double> onBlend;

  @override
  Widget build(BuildContext context) {
    var (value, onChanged) = switch (mode) {
      StageMode.slider => (split, onSplit),
      StageMode.onion => (blend, onBlend),
      _ => (null, null),
    };
    if (value == null || onChanged == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xl),
      child: Slider(value: value, onChanged: onChanged),
    );
  }
}

/// The largest box of [aspect] that fits inside [available].
Size _fit(double aspect, Size available) {
  if (available.width <= 0 || available.height <= 0 || aspect <= 0) {
    return Size.zero;
  }
  var byWidth = Size(available.width, available.width / aspect);
  return byWidth.height <= available.height
      ? byWidth
      : Size(available.height * aspect, available.height);
}
