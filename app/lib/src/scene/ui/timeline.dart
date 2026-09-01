import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../playback.dart';
import 'modifiers.dart';
import 'transport.dart';

/// The keyframe editor: one lane per animated track, keys as diamonds, the
/// playhead across all of them.
///
/// Rows are scene nodes — a group targets a node by name, so the gutter is
/// the node tree filtered to what moves — and every key drawn is a
/// [MotionKeyRef] the editor can select, nudge and delete as a set. A drag
/// goes through `nudgeKeys` with a merge key, so it is one undo entry
/// however far it went, and the sort door keeps the track ordered while it
/// moves. Groups the timeline does not place are a library beneath the
/// lanes; placing one is one command.
class SceneTimeline extends StatefulWidget {
  const SceneTimeline(
    this.editor,
    this.playback, {
    super.key,
    this.gutterWidth = 240,
    this.transport = true,
  });

  final SceneEditor editor;
  final ScenePlayback playback;
  final double gutterWidth;

  /// Whether the transport sits in the ruler's gutter. Off where the
  /// arrangement puts it on a toolbar instead.
  final bool transport;

  @override
  State<SceneTimeline> createState() => _SceneTimelineState();
}

class _SceneTimelineState extends State<SceneTimeline> {
  final _focus = FocusNode(debugLabel: 'scene timeline');

  SceneEditor get editor => widget.editor;
  ScenePlayback get playback => widget.playback;
  MotionDocument get motion => playback.motion;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// The lanes, in placement order: each animated node's tracks, with the
  /// group's start so a key draws at its absolute time.
  List<_Lane> _lanes() {
    var placements = motion.placements;
    var lanes = <_Lane>[];
    var placed = placements.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (var MapEntry(key: name, value: at) in placed) {
      var group = motion.groupNamed(name);
      if (group == null) continue;
      var first = true;
      for (var MapEntry(key: prop, value: track) in group.tracks.entries) {
        lanes.add(_Lane(group, prop, track, at, first: first));
        first = false;
      }
      for (var MapEntry(key: arg, value: track) in group.args.entries) {
        lanes.add(_Lane(group, 'args.$arg', track, at, first: first));
        first = false;
      }
    }
    return lanes;
  }

  Iterable<AnimateGroup> _unplaced() {
    var placed = motion.placements.keys.toSet();
    return motion.groups.where((g) => !placed.contains(g.name));
  }

  void _place(AnimateGroup group) {
    var at = playback.position;
    editor.perform('Place ${group.name}', () {
      var ref = GroupRef(group.name);
      var child = at == Duration.zero ? ref : AtExpr(at, ref);
      motion.timeline = switch (motion.timeline) {
        ParExpr p => ParExpr([...p.children, child]),
        var other => ParExpr([other, child]),
      };
    });
    playback.rebind();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return _TimelineShortcuts(
      editor: editor,
      playback: playback,
      focusNode: _focus,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          editor.listenable,
          editor.doc.listenable,
          playback,
        ]),
        builder: (context, _) {
          var lanes = _lanes();
          var unplaced = _unplaced().toList();
          var total = math.max(1, playback.duration.inMilliseconds);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 28,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: widget.gutterWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: FwSpacing.xs),
                        child: widget.transport
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: SceneTransport(playback, compact: true),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: FwSpacing.md,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    playback.motionName,
                                    style: context.type.bodyStrong,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    _gutterEdge(colors),
                    Expanded(
                      child: _Ruler(
                        duration: total,
                        t: playback.t,
                        onSeek: playback.seekT,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: colors.line),
              Expanded(
                child: lanes.isEmpty && unplaced.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing animates yet',
                          style: context.type.bodyMuted,
                        ),
                      )
                    : ListView(
                        children: [
                          for (var lane in lanes)
                            _LaneRow(
                              lane: lane,
                              editor: editor,
                              playback: playback,
                              total: total,
                              gutterWidth: widget.gutterWidth,
                            ),
                          if (unplaced.isNotEmpty)
                            _Library(
                              groups: unplaced,
                              gutterWidth: widget.gutterWidth,
                              onPlace: _place,
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _gutterEdge(FwPalette colors) =>
      Container(width: 1, color: colors.line);
}

class _Lane {
  const _Lane(
    this.group,
    this.prop,
    this.track,
    this.at, {
    required this.first,
  });

  final AnimateGroup group;
  final String prop;
  final MotionTrack track;

  /// Where the group starts on the timeline.
  final Duration at;

  /// The first lane of its group carries the node's name; the rest indent.
  final bool first;

  String get label => prop.startsWith('args.') ? prop.substring(5) : prop;
}

class _LaneRow extends StatelessWidget {
  const _LaneRow({
    required this.lane,
    required this.editor,
    required this.playback,
    required this.total,
    required this.gutterWidth,
  });

  final _Lane lane;
  final SceneEditor editor;
  final ScenePlayback playback;
  final int total;
  final double gutterWidth;

  static const height = 26.0;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var node = editor.doc.nodeNamed(lane.group.target);
    var hovered = node != null && editor.hover == node.name;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: gutterWidth,
            child: MouseRegion(
              onEnter: (_) => editor.hover = lane.group.target,
              onExit: (_) {
                if (editor.hover == lane.group.target) editor.hover = null;
              },
              child: Tappable(
                onTap: () => editor.select(node, toggle: toggleModifier),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: FwSpacing.lg,
                    right: FwSpacing.md,
                  ),
                  child: Row(
                    spacing: FwSpacing.sm,
                    children: [
                      SizedBox(
                        width: 84,
                        child: lane.first
                            ? Text(
                                lane.group.target,
                                overflow: TextOverflow.ellipsis,
                                style: context.type.body.copyWith(
                                  color: hovered
                                      ? colors.accentDark
                                      : colors.ink,
                                ),
                              )
                            : null,
                      ),
                      Expanded(
                        child: Text(
                          lane.label,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.caption.copyWith(
                            color: colors.mut,
                          ),
                        ),
                      ),
                      if (lane.first)
                        Flexible(
                          child: Text(
                            lane.group.name,
                            overflow: TextOverflow.ellipsis,
                            style: context.type.caption.copyWith(
                              color: colors.mut3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, color: colors.line),
          Expanded(
            child: _KeyStrip(
              lane: lane,
              editor: editor,
              playback: playback,
              total: total,
            ),
          ),
        ],
      ),
    );
  }
}

/// One lane's keys, hit and dragged in milliseconds.
class _KeyStrip extends StatefulWidget {
  const _KeyStrip({
    required this.lane,
    required this.editor,
    required this.playback,
    required this.total,
  });

  final _Lane lane;
  final SceneEditor editor;
  final ScenePlayback playback;
  final int total;

  @override
  State<_KeyStrip> createState() => _KeyStripState();
}

class _KeyStripState extends State<_KeyStrip> {
  /// Sub-millisecond drag carried to the next update, so a slow drag still
  /// moves the key.
  var _carried = 0.0;
  var _dragging = false;

  _Lane get lane => widget.lane;
  SceneEditor get editor => widget.editor;

  MotionKeyRef _ref(MotionKey key) => MotionKeyRef(
    widget.playback.motionName,
    lane.group.name,
    lane.prop,
    key.id,
  );

  double _x(MotionKey key, double width) =>
      (lane.at + key.at).inMilliseconds / widget.total * width;

  MotionKey? _hit(Offset local, double width) {
    MotionKey? best;
    var bestDistance = 7.0;
    for (var key in lane.track.keys) {
      var d = (local.dx - _x(key, width)).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = key;
      }
    }
    return best;
  }

  void _down(Offset local, double width) {
    var key = _hit(local, width);
    if (key == null) {
      editor.clearKeySelection();
      widget.playback.seekT(local.dx / width);
      return;
    }
    var ref = _ref(key);
    if (toggleModifier) {
      editor.selectKey(ref, toggle: true);
    } else if (!editor.isKeySelected(ref)) {
      editor.selectKey(ref);
    }
    _dragging = true;
    _carried = 0;
  }

  void _update(double dx, double width) {
    if (!_dragging) return;
    _carried += dx * widget.total / math.max(1.0, width);
    var whole = _carried.truncate();
    if (whole == 0) return;
    _carried -= whole;
    editor.nudgeKeys(Duration(milliseconds: whole), mergeKey: 'keydrag');
  }

  void _end() {
    if (!_dragging) return;
    _dragging = false;
    editor.endMerge();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = math.max(1.0, constraints.maxWidth);
        // The drag's own down, and no tap recognizer beside it: a tap is a
        // drag that never moved, and two recognizers both answering the
        // press toggled a shift-click twice.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragDown: (d) => _down(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _update(d.delta.dx, width),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          child: CustomPaint(
            painter: _KeyPainter(
              xs: [for (var k in lane.track.keys) _x(k, width)],
              selected: [
                for (var k in lane.track.keys) editor.isKeySelected(_ref(k)),
              ],
              spanStart: lane.at.inMilliseconds / widget.total * width,
              spanEnd:
                  (lane.at + lane.track.duration).inMilliseconds /
                  widget.total *
                  width,
              playhead: widget.playback.t * width,
              line: colors.line,
              key: colors.ink2,
              accent: colors.accent,
              playheadColor: colors.red,
            ),
          ),
        );
      },
    );
  }
}

class _KeyPainter extends CustomPainter {
  _KeyPainter({
    required this.xs,
    required this.selected,
    required this.spanStart,
    required this.spanEnd,
    required this.playhead,
    required this.line,
    required this.key,
    required this.accent,
    required this.playheadColor,
  });

  final List<double> xs;
  final List<bool> selected;
  final double spanStart;
  final double spanEnd;
  final double playhead;
  final Color line;
  final Color key;
  final Color accent;
  final Color playheadColor;

  @override
  void paint(Canvas canvas, Size size) {
    var mid = size.height / 2;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = line,
    );
    if (xs.isNotEmpty) {
      canvas.drawLine(
        Offset(spanStart, mid),
        Offset(spanEnd, mid),
        Paint()
          ..color = key.withValues(alpha: 0.35)
          ..strokeWidth = 2,
      );
    }
    for (var (i, x) in xs.indexed) {
      var on = selected[i];
      var r = on ? 5.5 : 4.5;
      var path = Path()
        ..moveTo(x, mid - r)
        ..lineTo(x + r, mid)
        ..lineTo(x, mid + r)
        ..lineTo(x - r, mid)
        ..close();
      canvas.drawPath(path, Paint()..color = on ? accent : key);
      if (on) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = accent.withValues(alpha: 0.4),
        );
      }
    }
    canvas.drawLine(
      Offset(playhead, 0),
      Offset(playhead, size.height),
      Paint()
        ..color = playheadColor.withValues(alpha: 0.8)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_KeyPainter old) => true;
}

/// Groups the timeline does not place yet. Placing one puts it on the
/// playhead.
class _Library extends StatelessWidget {
  const _Library({
    required this.groups,
    required this.gutterWidth,
    required this.onPlace,
  });

  final List<AnimateGroup> groups;
  final double gutterWidth;
  final ValueChanged<AnimateGroup> onPlace;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FwSpacing.lg,
        FwSpacing.lg,
        FwSpacing.lg,
        FwSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: FwSpacing.sm,
        children: [
          Text('LIBRARY', style: context.type.sectionLabel),
          Wrap(
            spacing: FwSpacing.xs,
            runSpacing: FwSpacing.xs,
            children: [
              for (var group in groups)
                Tooltip(
                  message: 'Place ${group.name} at the playhead',
                  child: Tappable(
                    onTap: () => onPlace(group),
                    borderRadius: BorderRadius.circular(context.radii.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FwSpacing.md,
                        vertical: FwSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.line),
                        borderRadius: BorderRadius.circular(context.radii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: FwSpacing.xs,
                        children: [
                          Text(group.name, style: context.type.caption),
                          Text(
                            '· ${group.target}',
                            style: context.type.caption.copyWith(
                              color: colors.mut2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ticks at a step that keeps about eight labels on screen whatever the
/// length, and the playhead's head. Drag anywhere to scrub.
class _Ruler extends StatelessWidget {
  const _Ruler({required this.duration, required this.t, required this.onSeek});

  final int duration;
  final double t;
  final ValueChanged<double> onSeek;

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
    var every = step(duration);
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = math.max(1.0, constraints.maxWidth);
        void seek(Offset local) => onSeek((local.dx / width).clamp(0.0, 1.0));
        return MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seek(d.localPosition),
            onHorizontalDragDown: (d) => seek(d.localPosition),
            onHorizontalDragUpdate: (d) => seek(d.localPosition),
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
                        if (ms / duration < 0.92)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: FwSpacing.xs,
                              top: FwSpacing.sm,
                            ),
                            child: Text(
                              _label(ms),
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
        );
      },
    );
  }

  static String _label(int ms) => ms % 1000 == 0 ? '${ms ~/ 1000}s' : '${ms}ms';
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

/// The timeline's focus scope: arrows step the selected keys, Backspace
/// deletes them, space plays. Its own scope rather than the canvas's, because
/// an arrow means a different thing to a key than to a node.
class _TimelineShortcuts extends StatelessWidget {
  const _TimelineShortcuts({
    required this.editor,
    required this.playback,
    required this.focusNode,
    required this.child,
  });

  final SceneEditor editor;
  final ScenePlayback playback;
  final FocusNode focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): editor.undo,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
          editor.redo,
      const SingleActivator(LogicalKeyboardKey.backspace): editor.deleteKeys,
      const SingleActivator(LogicalKeyboardKey.delete): editor.deleteKeys,
      const SingleActivator(LogicalKeyboardKey.escape):
          editor.clearKeySelection,
      const SingleActivator(LogicalKeyboardKey.space): playback.toggle,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => editor
          .nudgeKeys(const Duration(milliseconds: -10), mergeKey: 'keynudge'),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => editor
          .nudgeKeys(const Duration(milliseconds: 10), mergeKey: 'keynudge'),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
          editor.nudgeKeys(
            const Duration(milliseconds: -100),
            mergeKey: 'keynudge',
          ),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
          editor.nudgeKeys(
            const Duration(milliseconds: 100),
            mergeKey: 'keynudge',
          ),
    },
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => focusNode.requestFocus(),
      child: Focus(focusNode: focusNode, child: child),
    ),
  );
}
