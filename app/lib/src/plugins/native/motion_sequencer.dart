/// The sequencer: a ruler, a playhead, and one group per target over its lanes.
///
/// A View — it takes a parsed scope and callbacks, reads no core and holds no
/// session. What it does own is the drag in flight and which groups are
/// collapsed, both of which are display state that would be wrong to persist.
///
/// Laid out from the panel concept the design names: a fixed gutter carrying
/// state badge, target and indented properties; the track area to its right;
/// the playhead spanning every lane rather than living in the ruler alone,
/// because the thing you are lining up is one property against another.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/motion.dart' show curveByName, motionCurveNames;

import '../../motion/lane_model.dart';
import '../../motion/property_editor.dart';
import '../../motion/values_file.dart';
import '../../ui/design/spacing.dart';
import '../../ui/design/tokens.dart';
import '../../ui/tappable.dart';

/// Rewrites one segment in place. Every edit the panel makes — retime, trim,
/// re-value, re-curve — is this one call with a different closure.
typedef MotionEdit =
    Future<void> Function(
      String target,
      String property,
      int index,
      MotionSpan Function(MotionSpan) change,
    );

/// The gutter width, and the reason there is no separate target rail: an
/// outline panel beside lane names is the same information twice.
const _gutter = 196.0;
const _laneHeight = 26.0;
const _groupHeight = 28.0;

class MotionSequencer extends StatefulWidget {
  const MotionSequencer({
    super.key,
    required this.scope,
    required this.problems,
    required this.t,
    required this.selection,
    required this.onSelect,
    required this.onSeek,
    required this.onEdit,
    required this.onCreate,
  });

  final MotionScopeView? scope;
  final List<MotionFileProblem> problems;

  /// The playhead, 0..1 — the guest's, or a local drag while one is in flight.
  final double t;

  final MotionSelection? selection;
  final ValueChanged<MotionSelection?> onSelect;
  final ValueChanged<double> onSeek;
  final MotionEdit onEdit;
  final Future<void> Function(String target, String property) onCreate;

  @override
  State<MotionSequencer> createState() => _MotionSequencerState();
}

class _MotionSequencerState extends State<MotionSequencer> {
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    var scope = widget.scope;
    if (scope == null) {
      return Center(
        child: Text(
          'No motion mounted in the guest yet.',
          style: context.type.bodyMuted,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: _gutter),
            Expanded(
              child: _Ruler(
                duration: scope.durationMs,
                t: widget.t,
                onSeek: widget.onSeek,
              ),
            ),
          ],
        ),
        Divider(height: 1, color: context.colors.line),
        Expanded(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: FwSpacing.sm),
                children: [
                  // A refusal is shown, never swallowed. The editor declines to
                  // rewrite a values file it could not fully read, and a drag
                  // that silently did nothing would be indistinguishable from a
                  // broken one.
                  for (var problem in widget.problems)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FwSpacing.md,
                        vertical: FwSpacing.xs,
                      ),
                      child: Text(
                        'Not written — $problem',
                        style: context.type.caption.copyWith(
                          color: context.colors.red,
                        ),
                      ),
                    ),
                  for (var target in scope.targets)
                    ..._rowsFor(context, scope, target),
                ],
              ),
              // Outside the ListView so it stays put while the lanes scroll,
              // and offset past the gutter because it marks a time, not a row.
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      var track = math.max(1.0, constraints.maxWidth - _gutter);
                      return Stack(
                        children: [
                          Positioned(
                            left: _gutter + widget.t.clamp(0.0, 1.0) * track,
                            top: 0,
                            bottom: 0,
                            width: 1,
                            child: ColoredBox(color: context.colors.red),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _rowsFor(
    BuildContext context,
    MotionScopeView scope,
    MotionTargetView target,
  ) {
    var collapsed = _collapsed.contains(target.name);
    return [
      _GroupRow(
        target: target,
        duration: scope.durationMs,
        collapsed: collapsed,
        onToggle: () => setState(
          () => collapsed
              ? _collapsed.remove(target.name)
              : _collapsed.add(target.name),
        ),
        onSeek: widget.onSeek,
      ),
      if (!collapsed) ...[
        for (var property in target.properties)
          _LaneRow(
            key: ValueKey('${target.name}.${property.name}'),
            target: target.name,
            property: property,
            duration: scope.durationMs,
            selection: widget.selection,
            onSelect: widget.onSelect,
            onEdit: widget.onEdit,
            onCreate: () => widget.onCreate(target.name, property.name),
          ),
        if (target.addable.isNotEmpty)
          _AddRow(
            available: target.addable,
            onPick: (property) => widget.onCreate(target.name, property),
          ),
      ],
    ];
  }
}

/// Ticks, labels, and the whole width as a scrub surface.
class _Ruler extends StatelessWidget {
  const _Ruler({required this.duration, required this.t, required this.onSeek});

  final int duration;
  final double t;
  final ValueChanged<double> onSeek;

  /// A step that lands on a round number and leaves at most eight labels, so a
  /// 620ms motion is read in hundreds rather than in sevenths of itself.
  static int step(int duration) {
    for (var candidate in const [
      10,
      20,
      25,
      50,
      100,
      200,
      250,
      500,
      1000,
      2000,
      5000,
    ]) {
      if (duration / candidate <= 8) return candidate;
    }
    return duration <= 0 ? 1 : duration;
  }

  @override
  Widget build(BuildContext context) {
    if (duration <= 0) return const SizedBox(height: 24);
    var every = step(duration);

    return LayoutBuilder(
      builder: (context, constraints) {
        var width = math.max(1.0, constraints.maxWidth);
        void seek(Offset local) => onSeek((local.dx / width).clamp(0.0, 1.0));

        return MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => seek(details.localPosition),
            onHorizontalDragDown: (details) => seek(details.localPosition),
            onHorizontalDragUpdate: (details) => seek(details.localPosition),
            child: SizedBox(
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var ms = 0; ms <= duration; ms += every)
                    Positioned(
                      left: ms / duration * width,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 1,
                            child: ColoredBox(color: context.colors.line),
                          ),
                          // The tick still marks the time; only its label goes.
                          // A number half off the right edge reads as a
                          // different number, which is worse than no number.
                          if (ms / duration < 0.92)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, top: 4),
                              child: Text(
                                '$ms',
                                style: context.type.caption.copyWith(
                                  color: context.colors.mut2,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: t.clamp(0.0, 1.0) * width - 4.5,
                    top: 0,
                    child: CustomPaint(
                      size: const Size(9, 6),
                      painter: _PlayheadHead(context.colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayheadHead extends CustomPainter {
  _PlayheadHead(this.tone);

  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = tone,
    );
  }

  @override
  bool shouldRepaint(_PlayheadHead old) => old.tone != tone;
}

/// One target: a badge, a name, and a bar summarising every lane beneath it.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.target,
    required this.duration,
    required this.collapsed,
    required this.onToggle,
    required this.onSeek,
  });

  final MotionTargetView target;
  final int duration;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    var span = target.span;

    return SizedBox(
      height: _groupHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _gutter,
            child: Tappable(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
                child: Row(
                  spacing: FwSpacing.sm,
                  children: [
                    Icon(
                      collapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                      size: 14,
                      color: context.colors.mut2,
                    ),
                    _Badge(target.state),
                    Flexible(
                      child: Text(
                        target.name,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.body,
                      ),
                    ),
                    if (!target.named)
                      Tooltip(
                        message: 'Tuned, but no build asked for it — prunable.',
                        child: Icon(
                          Icons.link_off,
                          size: 12,
                          color: context.colors.amber,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // A group row carries no draggable span, so its whole track is free
          // to scrub — which is most of the sequencer's surface once the
          // targets are collapsed.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                var width = math.max(1.0, constraints.maxWidth);
                void seek(Offset local) =>
                    onSeek((local.dx / width).clamp(0.0, 1.0));
                return MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => seek(details.localPosition),
                    onHorizontalDragDown: (d) => seek(d.localPosition),
                    onHorizontalDragUpdate: (d) => seek(d.localPosition),
                    child: ColoredBox(
                      color: context.colors.panel2,
                      child: span == null || duration <= 0
                          ? const SizedBox.expand()
                          : CustomPaint(
                              painter: _AggregatePainter(
                                startMs: span.$1,
                                endMs: span.$2,
                                duration: duration,
                                tone: context.colors.mut3,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AggregatePainter extends CustomPainter {
  _AggregatePainter({
    required this.startMs,
    required this.endMs,
    required this.duration,
    required this.tone,
  });

  final int startMs;
  final int endMs;
  final int duration;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    var start = startMs / duration * size.width;
    var end = endMs / duration * size.width;
    var mid = size.height / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(start, mid - 3, math.max(end, start + 2), mid + 3),
        const Radius.circular(3),
      ),
      Paint()..color = tone,
    );
  }

  @override
  bool shouldRepaint(_AggregatePainter old) =>
      old.startMs != startMs ||
      old.endMs != endMs ||
      old.duration != duration ||
      old.tone != tone;
}

class _Badge extends StatelessWidget {
  const _Badge(this.state);

  final MotionLaneState state;

  @override
  Widget build(BuildContext context) {
    var (tone, hint) = switch (state) {
      MotionLaneState.wired => (context.colors.accent, 'Tuned and applied.'),
      MotionLaneState.dead => (
        context.colors.amber,
        'Tuned, and nothing reads it.',
      ),
      MotionLaneState.untuned => (
        context.colors.mut2,
        'Read, and nothing tunes it yet.',
      ),
    };
    return Tooltip(
      message: hint,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: state == MotionLaneState.untuned ? null : tone,
          border: state == MotionLaneState.untuned
              ? Border.all(color: tone, width: 1.5)
              : null,
        ),
      ),
    );
  }
}

class _LaneRow extends StatelessWidget {
  const _LaneRow({
    super.key,
    required this.target,
    required this.property,
    required this.duration,
    required this.selection,
    required this.onSelect,
    required this.onEdit,
    required this.onCreate,
  });

  final String target;
  final MotionPropertyView property;
  final int duration;
  final MotionSelection? selection;
  final ValueChanged<MotionSelection?> onSelect;
  final MotionEdit onEdit;

  /// Give this lane another tween. On a dashed lane that means the property
  /// starts existing; on a tuned one, a span at the playhead.
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    var tone = switch (property.state) {
      MotionLaneState.dead => context.colors.amber,
      MotionLaneState.untuned => context.colors.mut2,
      MotionLaneState.wired => context.colors.accent,
    };

    return SizedBox(
      height: _laneHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _gutter,
            child: Padding(
              padding: const EdgeInsets.only(left: 34, right: FwSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  property.name,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.caption.copyWith(
                    color: context.colors.mut,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _SpanStrip(
              segments: property.segments,
              duration: duration,
              tone: tone,
              dashed: property.state == MotionLaneState.untuned,
              selected:
                  selection?.target == target &&
                      selection?.property == property.name
                  ? selection?.index
                  : null,
              onSelect: (index) =>
                  onSelect(MotionSelection(target, property.name, index)),
              onCommit: (index, startMs, endMs) => onEdit(
                target,
                property.name,
                index,
                (span) => span.copyWith(startMs: startMs, endMs: endMs),
              ),
            ),
          ),
          Tooltip(
            message: property.segments.isEmpty
                ? 'Tune it — writes a first span into the values file.'
                : 'Add a span at the playhead, opening at the value it '
                      'already has there.',
            child: Tappable(
              onTap: onCreate,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
                child: Icon(Icons.add, size: 14, color: context.colors.accent),
              ),
            ),
          ),
          // Wide enough for `#FF1A1F26`, which is the longest thing a value can
          // be. It used to be, and then every lane gained a `+` and took the
          // room — so an eight-digit colour wrapped onto a second line inside a
          // 26px row and overflowed it.
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(right: FwSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: FwSpacing.xs,
                children: [
                  if (property.value case MotionColorView(:var color))
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: context.colors.line),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      property.value?.label ?? '—',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.caption.copyWith(
                        color: context.colors.mut,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `+ add property`, over what the target offers and nothing tunes.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.available, required this.onPick});

  final List<String> available;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _laneHeight,
      child: Row(
        children: [
          SizedBox(
            width: _gutter,
            child: MenuAnchor(
              menuChildren: [
                for (var property in available)
                  MenuItemButton(
                    onPressed: () => onPick(property),
                    child: Text(property, style: context.type.caption),
                  ),
              ],
              builder: (context, controller, _) => Tooltip(
                message:
                    'Applied by a MotionBox, not tuned. '
                    'Pick one to give it a span.',
                child: Tappable(
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '+ add property',
                        style: context.type.caption.copyWith(
                          color: context.colors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    );
  }
}

/// A lane's spans, draggable.
///
/// **The drag is held here and written once.** Every pointer sample used to be
/// a file read, a file write, a reload and a refresh — at roughly 1.5ms per
/// pixel on a 900ms motion that is a write on nearly every sample, sixty times
/// a second, and sixty entries in your editor's undo history for one gesture.
/// The bar follows the finger off a local copy, and the commit happens on
/// release.
///
/// The grab is decided once on the way down rather than re-derived per sample:
/// the middle third moves the whole span and the ends trim it, and re-deriving
/// would change what the drag means under the finger the moment a short span
/// passed beneath the cursor.
class _SpanStrip extends StatefulWidget {
  const _SpanStrip({
    required this.segments,
    required this.duration,
    required this.tone,
    required this.dashed,
    required this.selected,
    required this.onSelect,
    required this.onCommit,
  });

  final List<MotionSegmentView> segments;
  final int duration;
  final Color tone;
  final bool dashed;

  /// The index of the selected span in *this* lane, or null when the selection
  /// is elsewhere.
  final int? selected;

  final ValueChanged<int> onSelect;

  /// Called once, on release, with the span's settled bounds.
  final Future<void> Function(int index, int startMs, int endMs) onCommit;

  @override
  State<_SpanStrip> createState() => _SpanStripState();
}

enum _Grab { start, whole, end }

class _SpanStripState extends State<_SpanStrip> {
  int? _index;
  _Grab? _grab;

  /// Accumulated so a slow drag of a few pixels still lands as whole
  /// milliseconds instead of rounding to nothing on every sample.
  double _carried = 0;

  /// The bounds under the finger, or null when nothing is being dragged.
  ///
  /// While this is set it is what the lane draws, so the bar tracks the pointer
  /// without the file or the guest being involved at all.
  List<(int, int)>? _held;

  List<(int, int)> get _bounds =>
      _held ??
      [for (var segment in widget.segments) (segment.startMs, segment.endMs)];

  /// The span under a point, or null — the same hit test a grab and a tap need.
  int? _hit(Offset local, double width) {
    if (widget.duration <= 0) return null;
    for (var (index, (startMs, endMs)) in _bounds.indexed) {
      var start = startMs / widget.duration * width;
      var end = endMs / widget.duration * width;
      if (local.dx < start - 4 || local.dx > end + 4) continue;
      return index;
    }
    return null;
  }

  void _down(Offset local, double width) {
    var index = _hit(local, width);
    if (index == null) return;
    var bounds = _bounds;
    var (startMs, endMs) = bounds[index];
    var start = startMs / widget.duration * width;
    var end = endMs / widget.duration * width;
    // A zero-length span is a step keyframe and has no middle; the whole of
    // it grabs as one.
    var edge = ((end - start) / 3).clamp(0.0, 8.0);
    setState(() {
      _index = index;
      _grab = local.dx < start + edge
          ? _Grab.start
          : local.dx > end - edge
          ? _Grab.end
          : _Grab.whole;
      _carried = 0;
      _held = bounds;
    });
  }

  void _update(double dx, double width) {
    var index = _index;
    var grab = _grab;
    var held = _held;
    if (index == null || grab == null || held == null) return;
    _carried += dx * (widget.duration / width.clamp(1.0, double.infinity));
    var whole = _carried.truncate();
    if (whole == 0) return;
    _carried -= whole;

    var (startMs, endMs) = held[index];
    var total = widget.duration;
    // Clamped to the motion, and a span never turns inside out: an end dragged
    // past its start is a span that would evaluate backwards.
    var next = switch (grab) {
      _Grab.start => ((startMs + whole).clamp(0, endMs), endMs),
      _Grab.end => (startMs, (endMs + whole).clamp(startMs, total)),
      _Grab.whole => switch (whole.clamp(-startMs, total - endMs)) {
        var shift => (startMs + shift, endMs + shift),
      },
    };
    if (next == held[index]) return;
    setState(() => _held = [...held]..[index] = next);
  }

  Future<void> _release() async {
    var index = _index;
    var held = _held;
    setState(() {
      _index = null;
      _grab = null;
      _carried = 0;
    });
    if (index != null && held != null) {
      var (startMs, endMs) = held[index];
      await widget.onCommit(index, startMs, endMs);
    }
    // Cleared after the write, so the bar does not snap back to the guest's
    // old answer in the frames between committing and the reload landing.
    if (mounted) setState(() => _held = null);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => MouseRegion(
        cursor: widget.segments.isEmpty
            ? MouseCursor.defer
            : SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            var index = _hit(details.localPosition, constraints.maxWidth);
            if (index != null) widget.onSelect(index);
          },
          onHorizontalDragDown: (details) =>
              _down(details.localPosition, constraints.maxWidth),
          onHorizontalDragUpdate: (details) =>
              _update(details.delta.dx, constraints.maxWidth),
          onHorizontalDragEnd: (_) => unawaited(_release()),
          onHorizontalDragCancel: () => unawaited(_release()),
          child: CustomPaint(
            painter: _SpanPainter(
              bounds: _bounds,
              duration: widget.duration,
              tone: widget.tone,
              dashed: widget.dashed,
              grabbed: _index,
              selected: widget.selected,
              outline: context.colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpanPainter extends CustomPainter {
  _SpanPainter({
    required this.bounds,
    required this.duration,
    required this.tone,
    required this.dashed,
    required this.outline,
    this.grabbed,
    this.selected,
  });

  final List<(int, int)> bounds;
  final int duration;
  final Color tone;

  /// A property nothing tunes has no span to draw, so the lane is the outline
  /// of where one would go — which is the whole of the creation path.
  final bool dashed;

  final Color outline;

  /// The span under the finger, drawn solid so a drag has something to follow.
  final int? grabbed;

  /// The span the inspector is showing.
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    var mid = size.height / 2;
    var paint = Paint()..color = tone;
    if (bounds.isEmpty || duration <= 0) {
      if (!dashed) return;
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(
          Offset(x, mid),
          Offset((x + 3).clamp(0.0, size.width), mid),
          paint,
        );
      }
      return;
    }
    for (var (index, (startMs, endMs)) in bounds.indexed) {
      paint.color = index == grabbed ? tone : tone.withValues(alpha: 0.75);
      var start = startMs / duration * size.width;
      var end = endMs / duration * size.width;
      // A step keyframe is a zero-length span, and a zero-width rect draws
      // nothing at all — so it gets the minimum width that reads as a mark.
      var rect = Rect.fromLTRB(
        start,
        mid - 5,
        (end - start) < 2 ? start + 2 : end,
        mid + 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
      if (index == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(1.5), const Radius.circular(3)),
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpanPainter old) =>
      old.duration != duration ||
      old.tone != tone ||
      old.dashed != dashed ||
      old.grabbed != grabbed ||
      old.selected != selected ||
      old.outline != outline ||
      !const ListEquality<(int, int)>().equals(old.bounds, bounds);
}

/// The right-hand rail: what the selected segment is, in numbers you can type
/// over.
///
/// Every field here writes through the same `MotionEdit` the drag uses, so
/// there is one write path and one place that can refuse. A field that will not
/// parse simply does not commit — it keeps the text and leaves the file alone,
/// rather than writing a zero for what you meant.
class MotionInspector extends StatelessWidget {
  const MotionInspector({
    super.key,
    required this.scope,
    required this.selection,
    required this.onEdit,
    required this.onDelete,
  });

  final MotionScopeView? scope;
  final MotionSelection? selection;
  final MotionEdit onEdit;
  final Future<void> Function(MotionSelection selection) onDelete;

  @override
  Widget build(BuildContext context) {
    var scope = this.scope;
    var selection = this.selection;
    var segment = scope == null || selection == null
        ? null
        : scope.resolve(selection);

    return ColoredBox(
      color: context.colors.panel2,
      child: segment == null || selection == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.lg),
                child: Text(
                  'Select a span to see its values.',
                  textAlign: TextAlign.center,
                  style: context.type.bodyMuted,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(FwSpacing.lg),
              children: [
                _Heading('Segment'),
                const SizedBox(height: FwSpacing.sm),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: selection.target),
                      TextSpan(
                        text: ' · ${selection.property}',
                        style: TextStyle(color: context.colors.mut),
                      ),
                    ],
                  ),
                  style: context.type.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: FwSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: FwSpacing.md,
                  children: [
                    Expanded(
                      child: _NumberEditor(
                        label: 'Start',
                        value: segment.startMs.toDouble(),
                        shape: MotionNumberShape.milliseconds,
                        // Moves the span rather than trimming it. Dragging the
                        // middle is already what the lane means by a new start,
                        // and two gestures spelling the same edit differently
                        // is one too many.
                        onCommit: (value) => _change(selection, (span) {
                          var start = value.round();
                          return span.copyWith(
                            startMs: start,
                            endMs: start + span.durationMs,
                          );
                        }),
                      ),
                    ),
                    Expanded(
                      child: _NumberEditor(
                        label: 'Duration',
                        value: segment.durationMs.toDouble(),
                        shape: MotionNumberShape.milliseconds,
                        onCommit: (value) => _change(
                          selection,
                          (span) => span.copyWith(
                            endMs: span.startMs + value.round(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FwSpacing.md),
                // Side by side for numbers, stacked for colours: `#FF1A1F26`
                // does not fit half a 264px rail beside a swatch, and a value
                // cut off mid-hex reads as a different colour.
                if (segment.from is MotionColorView ||
                    segment.to is MotionColorView) ...[
                  _ValueEditor(
                    label: 'From',
                    value: segment.from,
                    property: selection.property,
                    onCommit: (value) => _change(
                      selection,
                      (span) => span.copyWith(from: value),
                    ),
                  ),
                  const SizedBox(height: FwSpacing.md),
                  _ValueEditor(
                    label: 'To',
                    value: segment.to,
                    property: selection.property,
                    onCommit: (value) =>
                        _change(selection, (span) => span.copyWith(to: value)),
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: FwSpacing.md,
                    children: [
                      Expanded(
                        child: _ValueEditor(
                          label: 'From',
                          value: segment.from,
                          property: selection.property,
                          onCommit: (value) => _change(
                            selection,
                            (span) => span.copyWith(from: value),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _ValueEditor(
                          label: 'To',
                          value: segment.to,
                          property: selection.property,
                          onCommit: (value) => _change(
                            selection,
                            (span) => span.copyWith(to: value),
                          ),
                        ),
                      ),
                    ],
                  ),
                // Said rather than left to be noticed. Most targets have no
                // extent — a target is not a widget — and a ring that silently
                // never appeared would read as a broken feature rather than as
                // one nobody has opted into here.
                if (scope?.target(selection.target)?.extent == null) ...[
                  const SizedBox(height: FwSpacing.lg),
                  _Note(
                    'No extent, so nothing is ringed on the stage. '
                    'Wrap it — MotionExtent(${selection.target}, child: …) — '
                    'to point at it. Applies nothing.',
                  ),
                ],
                const SizedBox(height: FwSpacing.lg),
                _Heading('Curve'),
                const SizedBox(height: FwSpacing.sm),
                _CurvePicker(
                  name: segment.curve,
                  onPick: (name) => _change(
                    selection,
                    // Not `copyWith`: it cannot put a curve back to none, since
                    // `curve ?? this.curve` reads null as "unchanged".
                    (span) => MotionSpan(
                      startMs: span.startMs,
                      endMs: span.endMs,
                      from: span.from,
                      to: span.to,
                      curve: name,
                    ),
                  ),
                ),
                const SizedBox(height: FwSpacing.xxl),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tappable(
                    onTap: () => unawaited(onDelete(selection)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: FwSpacing.sm,
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: context.colors.red,
                        ),
                        Text(
                          'Delete span',
                          style: context.type.caption.copyWith(
                            color: context.colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Returns the write, rather than firing and forgetting it.
  ///
  /// Whoever is holding a value under the finger has to know when the file and
  /// the guest have caught up; releasing before they have is what made every
  /// commit flash the old number for a frame.
  Future<void> _change(
    MotionSelection selection,
    MotionSpan Function(MotionSpan) change,
  ) => onEdit(selection.target, selection.property, selection.index, change);
}

/// A value, with whatever control its property earns.
///
/// One place decides colour-or-number, and `property_editor.dart` decides the
/// rest off the vocabulary — so adding a property to the closed set gives it an
/// editor without anybody touching this file.
/// A tuned value, with whatever control its property earns.
class _ValueEditor extends StatelessWidget {
  const _ValueEditor({
    required this.label,
    required this.value,
    required this.property,
    required this.onCommit,
  });

  final String label;
  final MotionValueView? value;
  final String property;
  final Future<void> Function(MotionLiteral) onCommit;

  @override
  Widget build(BuildContext context) {
    if (value case MotionColorView colour) {
      return _Field(
        label,
        colour.label,
        swatch: colour.color,
        onCommit: (text) {
          var hex = text.trim().replaceFirst(
            RegExp('^(#|0x)', caseSensitive: false),
            '',
          );
          var argb = int.tryParse(hex, radix: 16);
          if (argb != null && hex.length == 8) onCommit(MotionColor(argb));
        },
      );
    }

    return _NumberEditor(
      label: label,
      value: switch (value) {
        MotionNumberView(:var value) => value,
        _ => 0.0,
      },
      shape: shapeFor(property),
      onCommit: (next) => onCommit(MotionNumber(next)),
    );
  }
}

/// A number, its control, and the one copy of the value they are both showing.
///
/// **The in-flight value lives here, not in the controls.** A slider and the
/// number above it are two views of one thing; holding the dragged value in
/// each left them disagreeing for the length of every drag — the slider moved
/// and the number sat still, because the number was still showing what the file
/// said.
///
/// **And it is released only once the write has landed.** Clearing on pointer-up
/// dropped back to the file's value for the frames between committing and the
/// reload arriving, which is a flash of the old number on every single edit. It
/// is the same rule the span drag already followed and the reason its comment
/// says "cleared after the write".
class _NumberEditor extends StatefulWidget {
  const _NumberEditor({
    required this.label,
    required this.value,
    required this.shape,
    required this.onCommit,
  });

  final String label;

  /// In stored units — radians for an angle, milliseconds for a duration.
  final double value;

  final MotionNumberShape shape;
  final Future<void> Function(double value) onCommit;

  @override
  State<_NumberEditor> createState() => _NumberEditorState();
}

class _NumberEditorState extends State<_NumberEditor> {
  double? _held;

  double get _shown => _held ?? widget.value;

  void _change(double next) =>
      setState(() => _held = widget.shape.clampStored(next));

  Future<void> _commit(double next) async {
    var settled = widget.shape.clampStored(next);
    // A press with no movement still ends a drag, and rewriting the file with
    // the value it already holds is a diff nobody asked for and an undo entry
    // that undoes nothing.
    if (settled == widget.value) {
      if (_held != null) setState(() => _held = null);
      return;
    }
    setState(() => _held = settled);
    await widget.onCommit(settled);
    if (mounted) setState(() => _held = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: context.type.caption.copyWith(color: context.colors.mut),
        ),
        const SizedBox(height: 3),
        _ScrubNumber(
          value: _shown,
          shape: widget.shape,
          held: _held != null,
          onChanged: _change,
          onCommit: _commit,
        ),
        switch (widget.shape.editor) {
          MotionEditorShape.scrub => const SizedBox.shrink(),
          MotionEditorShape.slider => _BoundedSlider(
            value: _shown,
            shape: widget.shape,
            onChanged: _change,
            onCommit: _commit,
          ),
          MotionEditorShape.dial => _AngleDial(
            value: _shown,
            shape: widget.shape,
            onChanged: _change,
            onCommit: _commit,
          ),
        },
      ],
    );
  }
}

/// A number you drag, and click to type.
///
/// Drag-to-scrub rather than a text field you must select and retype: the thing
/// you want nine times out of ten is *a bit more*, and a field makes you spell
/// out a whole number to say it. The pixel-to-value rate comes from the shape,
/// so the same gesture means a sensible amount whether the value runs 0..1 or
/// 0..620.
///
/// Controlled — the value under the finger belongs to [_NumberEditor], which is
/// also showing it on a slider or a dial.
class _ScrubNumber extends StatefulWidget {
  const _ScrubNumber({
    required this.value,
    required this.shape,
    required this.held,
    required this.onChanged,
    required this.onCommit,
  });

  final double value;
  final MotionNumberShape shape;

  /// Whether a drag is in flight anywhere in this editor, so the border says so
  /// even when the drag is on the slider.
  final bool held;

  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  @override
  State<_ScrubNumber> createState() => _ScrubNumberState();
}

class _ScrubNumberState extends State<_ScrubNumber> {
  var _typing = false;
  late final _controller = TextEditingController();
  late final _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus && _typing) _commitTyped();
  }

  void _startTyping() {
    setState(() {
      _typing = true;
      _controller.text = widget.shape.format(widget.value);
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
    _focus.requestFocus();
  }

  void _commitTyped() {
    var shown = double.tryParse(_controller.text.trim());
    setState(() => _typing = false);
    // Refuses rather than writing a zero for what somebody meant.
    if (shown == null) return;
    widget.onCommit(widget.shape.fromDisplay(shown));
  }

  void _drag(double dx) {
    var shown =
        widget.shape.toDisplay(widget.value) + dx * widget.shape.perPixel;
    widget.onChanged(widget.shape.fromDisplay(shown));
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var unit = widget.shape.unit;
    return Container(
      height: 27,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.bg,
        border: Border.all(
          color: widget.held ? context.colors.accent : context.colors.line,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: _typing
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    onSubmitted: (_) => _commitTyped(),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: context.type.caption.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    unit,
                    style: context.type.caption.copyWith(
                      color: context.colors.mut2,
                    ),
                  ),
              ],
            )
          : MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _startTyping,
                onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
                onHorizontalDragEnd: (_) => widget.onCommit(widget.value),
                onHorizontalDragCancel: () => widget.onCommit(widget.value),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.shape.format(widget.value),
                        style: context.type.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (unit.isNotEmpty)
                      Text(
                        unit,
                        style: context.type.caption.copyWith(
                          color: context.colors.mut2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// For a value whose soft range *is* its meaning — an opacity of 0.5 is half,
/// and where it sits between 0 and 1 is the whole of what you want to see.
class _BoundedSlider extends StatelessWidget {
  const _BoundedSlider({
    required this.value,
    required this.shape,
    required this.onChanged,
    required this.onCommit,
  });

  final double value;
  final MotionNumberShape shape;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    var (min, max) = shape.displayRange;
    var shown = shape.toDisplay(value);
    return SizedBox(
      height: 22,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
        ),
        child: Slider(
          // A hint, not a clamp — so a value the file already carries beyond
          // the soft range widens the slider rather than being dragged back
          // inside it the moment you touch the control.
          min: math.min(min, shown),
          max: math.max(max, shown),
          value: shown,
          onChanged: (next) => onChanged(shape.fromDisplay(next)),
          onChangeEnd: (next) => onCommit(shape.fromDisplay(next)),
        ),
      ),
    );
  }
}

/// A dial, for angles.
///
/// A number of degrees answers "how far"; only a dial answers "which way",
/// which is the question you actually have about a rotation. Zero is at twelve
/// o'clock and positive winds clockwise, matching `Transform.rotate` — which is
/// where these values are read.
///
/// The drag accumulates the *change* in pointer angle rather than snapping to
/// it, so winding past a full turn keeps going instead of wrapping back to
/// zero, and a 540° rotation stays expressible.
class _AngleDial extends StatefulWidget {
  const _AngleDial({
    required this.value,
    required this.shape,
    required this.onChanged,
    required this.onCommit,
  });

  final double value;
  final MotionNumberShape shape;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onCommit;

  @override
  State<_AngleDial> createState() => _AngleDialState();
}

class _AngleDialState extends State<_AngleDial> {
  static const _size = 34.0;

  double? _lastPointer;

  double _pointerAngle(Offset local) {
    var centre = const Offset(_size / 2, _size / 2);
    var v = local - centre;
    // Zero at twelve o'clock, clockwise positive.
    return math.atan2(v.dx, -v.dy);
  }

  void _update(Offset local) {
    var angle = _pointerAngle(local);
    var last = _lastPointer;
    _lastPointer = angle;
    if (last == null) return;
    var delta = angle - last;
    // The short way round, so crossing twelve o'clock does not jump a turn.
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    widget.onChanged(widget.value + delta);
  }

  void _release() {
    _lastPointer = null;
    widget.onCommit(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FwSpacing.xs),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _lastPointer = _pointerAngle(d.localPosition),
          onPanUpdate: (d) => _update(d.localPosition),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: CustomPaint(
            size: const Size(_size, _size),
            painter: _DialPainter(
              radians: widget.value,
              tone: context.colors.accent,
              rim: context.colors.line,
              face: context.colors.bg,
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.radians,
    required this.tone,
    required this.rim,
    required this.face,
  });

  final double radians;
  final Color tone;
  final Color rim;
  final Color face;

  @override
  void paint(Canvas canvas, Size size) {
    var centre = size.center(Offset.zero);
    var radius = size.shortestSide / 2 - 1;

    canvas
      ..drawCircle(centre, radius, Paint()..color = face)
      ..drawCircle(
        centre,
        radius,
        Paint()
          ..color = rim
          ..style = PaintingStyle.stroke,
      )
      // The mark at twelve, so "which way" has something to be measured from.
      ..drawLine(
        centre + Offset(0, -radius),
        centre + Offset(0, -radius + 3),
        Paint()
          ..color = rim
          ..strokeWidth = 1,
      )
      ..drawLine(
        centre,
        centre + Offset(math.sin(radians), -math.cos(radians)) * (radius - 2),
        Paint()
          ..color = tone
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(centre, 2, Paint()..color = tone);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.radians != radians ||
      old.tone != tone ||
      old.rim != rim ||
      old.face != face;
}

/// An aside in the rail, with an amber edge — the shape the spec gives the
/// "needs wiring" snippet, which lands here too.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: FwSpacing.md,
      vertical: FwSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: context.colors.panel,
      border: Border(
        left: BorderSide(color: context.colors.amber, width: 2),
        top: BorderSide(color: context.colors.line),
        right: BorderSide(color: context.colors.line),
        bottom: BorderSide(color: context.colors.line),
      ),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: context.type.caption.copyWith(color: context.colors.ink2),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: context.type.caption.copyWith(
      color: context.colors.mut2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
    ),
  );
}

/// A labelled box you can type into.
///
/// The controller is seeded once and refreshed only while the field is *not*
/// focused: a poll lands every second, and re-seeding under the cursor would
/// take the text out from under whoever is typing it.
class _Field extends StatefulWidget {
  const _Field(this.label, this.text, {required this.onCommit, this.swatch});

  final String label;
  final String text;
  final Color? swatch;
  final ValueChanged<String> onCommit;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _controller = TextEditingController(text: widget.text);
  late final _focus = FocusNode()..addListener(_onFocus);

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.text != _controller.text) {
      _controller.text = widget.text;
    }
  }

  void _onFocus() {
    // Commit on the way out as well as on submit, because tabbing away from a
    // field you just edited is the commonest way to mean "yes, that one".
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_controller.text == widget.text) return;
    widget.onCommit(_controller.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: context.type.caption.copyWith(color: context.colors.mut),
        ),
        const SizedBox(height: 3),
        Container(
          height: 27,
          padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
          decoration: BoxDecoration(
            color: context.colors.bg,
            border: Border.all(color: context.colors.line),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            spacing: FwSpacing.sm,
            children: [
              if (widget.swatch case var colour?)
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: context.colors.line),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onSubmitted: (_) => _commit(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: context.type.caption.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The curve box, opened as a menu over every curve the writer can spell.
///
/// The list is [motionCurveNames] rather than one kept here, so a picker can
/// never offer a name the writer would then refuse.
class _CurvePicker extends StatelessWidget {
  const _CurvePicker({required this.name, required this.onPick});

  final String? name;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => onPick(null),
          child: Text('Default', style: context.type.caption),
        ),
        for (var candidate in motionCurveNames)
          MenuItemButton(
            onPressed: () => onPick(candidate),
            leadingIcon: Icon(
              candidate == name ? Icons.check : null,
              size: 14,
              color: context.colors.accent,
            ),
            child: Text(candidate, style: context.type.caption),
          ),
      ],
      builder: (context, controller, _) => Tappable(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: _CurveBox(name),
      ),
    );
  }
}

/// The easing, plotted from the curve the file names.
///
/// It plots by *sampling the curve itself* rather than by drawing stored
/// control points, so a name this runtime cannot resolve draws nothing and says
/// so — which is the same answer the writer would give.
class _CurveBox extends StatelessWidget {
  const _CurveBox(this.name);

  final String? name;

  @override
  Widget build(BuildContext context) {
    var name = this.name;
    var curve = name == null ? null : curveByName(name);

    return Container(
      padding: const EdgeInsets.all(FwSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.bg,
        border: Border.all(color: context.colors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        spacing: FwSpacing.lg,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: context.colors.panel2,
              borderRadius: BorderRadius.circular(4),
            ),
            child: curve == null
                ? null
                : CustomPaint(
                    painter: _CurvePainter(
                      curve: curve,
                      tone: context.colors.accent,
                      axis: context.colors.line,
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              name == null
                  ? 'Default'
                  : curve == null
                  ? '$name — not a curve this editor writes'
                  : 'Curves.$name',
              style: context.type.caption.copyWith(
                color: curve == null && name != null
                    ? context.colors.amber
                    : context.colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.curve, required this.tone, required this.axis});

  final Curve curve;
  final Color tone;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 4.0;
    var left = pad;
    var right = size.width - pad;
    var top = pad;
    var bottom = size.height - pad;

    canvas.drawLine(
      Offset(left, bottom),
      Offset(right, bottom),
      Paint()..color = axis,
    );
    canvas.drawLine(
      Offset(left, bottom),
      Offset(left, top),
      Paint()..color = axis,
    );

    var path = Path();
    // Elastic and bounce overshoot 0..1, so the plot is scaled to what the
    // curve actually reaches rather than clipped at the box.
    var samples = [
      for (var i = 0; i <= 32; i++) (i / 32, curve.transform(i / 32)),
    ];
    var lo = math.min(0.0, samples.map((s) => s.$2).reduce(math.min));
    var hi = math.max(1.0, samples.map((s) => s.$2).reduce(math.max));
    for (var (index, (t, value)) in samples.indexed) {
      var x = left + t * (right - left);
      var y = bottom - (value - lo) / (hi - lo) * (bottom - top);
      index == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = tone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.curve != curve || old.tone != tone || old.axis != axis;
}
