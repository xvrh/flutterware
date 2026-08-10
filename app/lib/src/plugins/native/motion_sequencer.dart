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
import 'package:flutterware/motion.dart' show curveByName;

import '../../motion/lane_model.dart';
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
    required this.onSeekEnd,
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
  final VoidCallback onSeekEnd;
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
                onSeekEnd: widget.onSeekEnd,
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
        onSeekEnd: widget.onSeekEnd,
      ),
      if (!collapsed) ...[
        for (var (index, property) in target.properties.indexed)
          _LaneRow(
            key: ValueKey('${target.name}.${property.name}'),
            target: target.name,
            property: property,
            duration: scope.durationMs,
            selection: widget.selection,
            onSelect: widget.onSelect,
            onEdit: widget.onEdit,
            onCreate: property.state == MotionLaneState.untuned
                ? () => widget.onCreate(target.name, property.name)
                : null,
            zebra: index.isOdd,
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
  const _Ruler({
    required this.duration,
    required this.t,
    required this.onSeek,
    required this.onSeekEnd,
  });

  final int duration;
  final double t;
  final ValueChanged<double> onSeek;
  final VoidCallback onSeekEnd;

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
            onTapDown: (details) {
              seek(details.localPosition);
              onSeekEnd();
            },
            onHorizontalDragDown: (details) => seek(details.localPosition),
            onHorizontalDragUpdate: (details) => seek(details.localPosition),
            onHorizontalDragEnd: (_) => onSeekEnd(),
            onHorizontalDragCancel: onSeekEnd,
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
    required this.onSeekEnd,
  });

  final MotionTargetView target;
  final int duration;
  final bool collapsed;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;
  final VoidCallback onSeekEnd;

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
                    onTapDown: (details) {
                      seek(details.localPosition);
                      onSeekEnd();
                    },
                    onHorizontalDragDown: (d) => seek(d.localPosition),
                    onHorizontalDragUpdate: (d) => seek(d.localPosition),
                    onHorizontalDragEnd: (_) => onSeekEnd(),
                    onHorizontalDragCancel: onSeekEnd,
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
    required this.zebra,
    this.onCreate,
  });

  final String target;
  final MotionPropertyView property;
  final int duration;
  final MotionSelection? selection;
  final ValueChanged<MotionSelection?> onSelect;
  final MotionEdit onEdit;
  final bool zebra;

  /// Set only on a dashed lane: the code reads this and nothing tunes it.
  final VoidCallback? onCreate;

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
          if (onCreate case var create?)
            Tooltip(
              message: 'Tune it — writes a first span into the values file.',
              child: Tappable(
                onTap: create,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FwSpacing.sm),
                  child: Icon(
                    Icons.add,
                    size: 14,
                    color: context.colors.accent,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: onCreate == null ? 92 : 62,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: FwSpacing.md),
                child: Text(
                  property.value?.label ?? '—',
                  style: context.type.caption.copyWith(
                    color: context.colors.mut,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// The right-hand rail: what the selected segment is, in numbers.
///
/// Read-only for now. It is where the values, the timing and the easing become
/// visible at all — until this existed the panel could retime a span and never
/// say what the span was worth at either end.
class MotionInspector extends StatelessWidget {
  const MotionInspector({
    super.key,
    required this.scope,
    required this.selection,
  });

  final MotionScopeView? scope;
  final MotionSelection? selection;

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
                  spacing: FwSpacing.md,
                  children: [
                    Expanded(child: _Field('Start', '${segment.startMs} ms')),
                    Expanded(
                      child: _Field('Duration', '${segment.durationMs} ms'),
                    ),
                  ],
                ),
                const SizedBox(height: FwSpacing.md),
                Row(
                  spacing: FwSpacing.md,
                  children: [
                    Expanded(child: _Field.value('From', segment.from)),
                    Expanded(child: _Field.value('To', segment.to)),
                  ],
                ),
                const SizedBox(height: FwSpacing.lg),
                _Heading('Curve'),
                const SizedBox(height: FwSpacing.sm),
                _CurveBox(segment.curve),
              ],
            ),
    );
  }
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

class _Field extends StatelessWidget {
  const _Field(this.label, this.text, {this.swatch});

  /// A value field, which is the same box plus a swatch when it is a colour.
  factory _Field.value(String label, MotionValueView? value) => _Field(
    label,
    value?.label ?? '—',
    swatch: value is MotionColorView ? value.color : null,
  );

  final String label;
  final String text;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
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
              if (swatch case var colour?)
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: context.colors.line),
                  ),
                ),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
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
