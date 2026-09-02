import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/split_button.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../playback.dart';
import 'modifiers.dart';
import 'shortcuts.dart';
import 'transport.dart';

/// The keyframe editor: one lane per animated track, keys as diamonds, the
/// playhead across all of them.
///
/// Rows are scene nodes — a group targets a node by name, so the gutter is
/// the node tree filtered to what moves — and every key drawn is a
/// [MotionKeyRef] the editor can select, nudge and delete as a set. A drag
/// goes through `nudgeKeys` with a merge key, so it is one undo entry
/// however far it went, and the sort door keeps the track ordered while it
/// moves.
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

  /// The placed groups in document order, each with its lanes — one per
  /// track, with the group's start so a key draws at its absolute time.
  ///
  /// Document order, not start order: a row that sorted by start would move
  /// while its bar is being dragged past a neighbour, and a drag whose row
  /// walks away under the pointer is how one gesture came to move two groups.
  List<_GroupLanes> _groups() {
    var placements = motion.placements;
    var out = <_GroupLanes>[];
    for (var group in motion.groups) {
      // A group the timeline expression does not place — legal in a
      // hand-edited file — is shown at zero; dragging its bar places it.
      var at = placements[group.name] ?? Duration.zero;
      out.add(
        _GroupLanes(group, at, [
          for (var MapEntry(key: prop, value: track) in group.tracks.entries)
            _Lane(group, prop, track, at),
          for (var MapEntry(key: arg, value: track) in group.args.entries)
            _Lane(group, 'args.$arg', track, at),
        ]),
      );
    }
    return out;
  }

  /// A key on [prop] of [group], at the playhead — the door every "animate
  /// this" gesture ends in. A group that is not placed cannot take the
  /// playhead's time; it gets a key at its own zero.
  void _keyAtPlayhead(AnimateGroup group, String prop) {
    var at = motion.placements[group.name];
    var t = at == null ? Duration.zero : playback.position - at;
    editor.addKey(
      playback.motionName,
      group.name,
      prop,
      t < Duration.zero ? Duration.zero : t,
    );
  }

  /// The selected node's first group — made and placed at zero when it has
  /// none — then a key on [prop] at the playhead.
  void _animateSelected(SceneNode node, String prop) {
    var group =
        editor.groupsTargeting(playback.motionName, node).firstOrNull ??
        editor.addGroup(playback.motionName, node);
    _keyAtPlayhead(group, prop);
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
          var groups = _groups();
          var total = math.max(1, playback.duration.inMilliseconds);
          var selected = editor.primary;
          var selectedName = selected?.name;
          var selectedHasGroup = groups.any(
            (g) => g.group.target == selectedName,
          );
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
                child: groups.isEmpty && selected == null
                    ? Center(
                        child: Text(
                          'Nothing animates yet — select a node to animate it',
                          style: context.type.bodyMuted,
                        ),
                      )
                    : ListView(
                        children: [
                          for (var g in groups) ...[
                            _GroupRow(
                              key: ValueKey('group:${g.group.name}'),
                              lanes: g,
                              editor: editor,
                              playback: playback,
                              total: total,
                              gutterWidth: widget.gutterWidth,
                              onAddKey: (prop) => _keyAtPlayhead(g.group, prop),
                            ),
                            for (var lane in g.lanes)
                              _LaneRow(
                                key: ValueKey(
                                  'lane:${g.group.name}/${lane.prop}',
                                ),
                                lane: lane,
                                editor: editor,
                                playback: playback,
                                total: total,
                                gutterWidth: widget.gutterWidth,
                              ),
                          ],
                          if (selected != null && !selectedHasGroup)
                            _AnimateRow(
                              node: selected,
                              gutterWidth: widget.gutterWidth,
                              onPick: (prop) =>
                                  _animateSelected(selected, prop),
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
  const _Lane(this.group, this.prop, this.track, this.at);

  final AnimateGroup group;
  final String prop;
  final MotionTrack track;

  /// Where the group starts on the timeline.
  final Duration at;

  String get label => prop.startsWith('args.') ? prop.substring(5) : prop;
}

/// A placed group and the lanes under it.
class _GroupLanes {
  const _GroupLanes(this.group, this.at, this.lanes);

  final AnimateGroup group;
  final Duration at;
  final List<_Lane> lanes;
}

/// The row a group gets above its lanes: its node and its name in the
/// gutter with the door to a new track, and in the strip a bar spanning its
/// length — dragging the bar moves the whole group on the timeline.
class _GroupRow extends StatefulWidget {
  const _GroupRow({
    super.key,
    required this.lanes,
    required this.editor,
    required this.playback,
    required this.total,
    required this.gutterWidth,
    required this.onAddKey,
  });

  final _GroupLanes lanes;
  final SceneEditor editor;
  final ScenePlayback playback;
  final int total;
  final double gutterWidth;
  final ValueChanged<String> onAddKey;

  static const height = 26.0;

  @override
  State<_GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<_GroupRow> {
  var _carried = 0.0;
  var _dragging = false;

  AnimateGroup get group => widget.lanes.group;
  SceneEditor get editor => widget.editor;

  void _down(Offset local, double width) {
    var start = widget.lanes.at.inMilliseconds / widget.total * width;
    var end =
        (widget.lanes.at + group.duration).inMilliseconds /
        widget.total *
        width;
    if (local.dx < start - 4 || local.dx > end + 4) {
      widget.playback.seekT(local.dx / width);
      return;
    }
    editor.select(editor.doc.nodeNamed(group.target));
    _dragging = true;
    _carried = 0;
  }

  void _update(double dx, double width) {
    if (!_dragging) return;
    _carried += dx * widget.total / math.max(1.0, width);
    var whole = _carried.truncate();
    if (whole == 0) return;
    _carried -= whole;
    var at = widget.playback.motion.placements[group.name] ?? Duration.zero;
    editor.moveGroup(
      widget.playback.motionName,
      group.name,
      at + Duration(milliseconds: whole),
      mergeKey: 'groupdrag',
    );
  }

  void _end() {
    if (!_dragging) return;
    _dragging = false;
    editor.endMerge();
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var node = editor.doc.nodeNamed(group.target);
    var tracked = {
      ...group.tracks.keys,
      ...group.args.keys.map((a) => 'args.$a'),
    };
    var offered = node == null
        ? const <ScenePropSpec>[]
        : animatableProps(node).where((p) => !tracked.contains(p.name));
    var hovered = editor.hover == group.target;
    var selected = node != null && editor.isSelected(node);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (d) => showContextMenu(context, d.globalPosition, [
        MenuItem(
          'Delete ${group.name}',
          icon: Icons.close,
          danger: true,
          onSelected: () =>
              editor.deleteGroup(widget.playback.motionName, group.name),
        ),
      ]),
      child: SizedBox(
        height: _GroupRow.height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: widget.gutterWidth,
              child: MouseRegion(
                onEnter: (_) => editor.hover = group.target,
                onExit: (_) {
                  if (editor.hover == group.target) editor.hover = null;
                },
                child: Tappable(
                  onTap: () => editor.select(node, toggle: toggleModifier),
                  child: Container(
                    color: selected ? colors.accentSoft : null,
                    padding: const EdgeInsets.only(
                      left: FwSpacing.lg,
                      right: FwSpacing.xs,
                    ),
                    child: Row(
                      spacing: FwSpacing.sm,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: group.target,
                              style: context.type.body.copyWith(
                                color: hovered || selected
                                    ? colors.accentDark
                                    : colors.ink,
                              ),
                              children: [
                                TextSpan(
                                  text: '  ${group.name}',
                                  style: context.type.caption.copyWith(
                                    color: colors.mut3,
                                  ),
                                ),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (offered.isNotEmpty)
                          Tooltip(
                            message: 'Animate another property, keyed at the playhead',
                            child: FwSplitButton.icon(
                              icon: Icons.add,
                              menuTooltip: 'Properties',
                              entries: [
                                for (var spec in offered)
                                  MenuItem(
                                    spec.name.startsWith('args.')
                                        ? spec.name.substring(5)
                                        : spec.name,
                                    onSelected: () =>
                                        widget.onAddKey(spec.name),
                                  ),
                              ],
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  var width = math.max(1.0, constraints.maxWidth);
                  return MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onHorizontalDragDown: (d) =>
                          _down(d.localPosition, width),
                      onHorizontalDragUpdate: (d) => _update(d.delta.dx, width),
                      onHorizontalDragEnd: (_) => _end(),
                      onHorizontalDragCancel: _end,
                      child: CustomPaint(
                        painter: _SpanPainter(
                          start:
                              widget.lanes.at.inMilliseconds /
                              widget.total *
                              width,
                          end:
                              (widget.lanes.at + group.duration)
                                  .inMilliseconds /
                              widget.total *
                              width,
                          playhead: widget.playback.t * width,
                          fill: selected
                              ? colors.accentSoft2
                              : colors.accentSoft,
                          edge: colors.accent,
                          line: colors.line,
                          playheadColor: colors.red,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpanPainter extends CustomPainter {
  _SpanPainter({
    required this.start,
    required this.end,
    required this.playhead,
    required this.fill,
    required this.edge,
    required this.line,
    required this.playheadColor,
  });

  final double start;
  final double end;
  final double playhead;
  final Color fill;
  final Color edge;
  final Color line;
  final Color playheadColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = line,
    );
    var bar = RRect.fromRectAndRadius(
      Rect.fromLTRB(start, 6, math.max(end, start + 4), size.height - 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(bar, Paint()..color = fill);
    canvas.drawRRect(
      bar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge.withValues(alpha: 0.6),
    );
    canvas.drawLine(
      Offset(playhead, 0),
      Offset(playhead, size.height),
      Paint()
        ..color = playheadColor.withValues(alpha: 0.8)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SpanPainter old) => true;
}

/// The row a selected node gets when nothing animates it yet: pick a
/// property, and a group is made for it with a key at the playhead.
class _AnimateRow extends StatelessWidget {
  const _AnimateRow({
    required this.node,
    required this.gutterWidth,
    required this.onPick,
  });

  final SceneNode node;
  final double gutterWidth;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return SizedBox(
      height: _GroupRow.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(
                left: FwSpacing.lg,
                right: FwSpacing.xs,
              ),
              child: Row(
                spacing: FwSpacing.sm,
                children: [
                  Expanded(
                    child: Text(
                      node.name,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.body.copyWith(color: colors.mut),
                    ),
                  ),
                  Tooltip(
                    message: 'Animate ${node.name} — a key at the playhead',
                    child: FwSplitButton.icon(
                      icon: Icons.add,
                      menuTooltip: 'Properties',
                      entries: [
                        for (var spec in animatableProps(node))
                          MenuItem(
                            spec.name.startsWith('args.')
                                ? spec.name.substring(5)
                                : spec.name,
                            onSelected: () => onPick(spec.name),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, color: colors.line),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.line)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaneRow extends StatelessWidget {
  const _LaneRow({
    super.key,
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
                    left: FwSpacing.xxl + FwSpacing.md,
                    right: FwSpacing.md,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      lane.label,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.caption.copyWith(
                        color: hovered ? colors.accentDark : colors.mut,
                      ),
                    ),
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

  /// Where the second tap of a double-tap landed: the recognizer reports the
  /// position on its down and the gesture on its up.
  Offset? _doubleTapAt;

  void _addKeyAt(double width) {
    var local = _doubleTapAt;
    if (local == null) return;
    var t =
        Duration(milliseconds: (local.dx / width * widget.total).round()) -
        lane.at;
    editor.addKey(
      widget.playback.motionName,
      lane.group.name,
      lane.prop,
      t < Duration.zero ? Duration.zero : t,
    );
  }

  /// Right-click: on a key, the key's verbs; anywhere on the lane, the
  /// track's and the group's.
  void _contextMenu(BuildContext context, TapUpDetails d, double width) {
    var key = _hit(d.localPosition, width);
    var motion = widget.playback.motionName;
    if (key != null) {
      var ref = _ref(key);
      if (!editor.isKeySelected(ref)) editor.selectKey(ref);
    }
    var selected = editor.selectedKeys.length;
    showContextMenu(context, d.globalPosition, [
      if (key != null) ...[
        MenuItem(
          selected > 1 ? 'Delete $selected keys' : 'Delete key',
          icon: Icons.close,
          shortcut: '⌫',
          danger: true,
          onSelected: editor.deleteKeys,
        ),
        const MenuDivider(),
      ],
      MenuItem(
        'Add key here',
        icon: Icons.add,
        onSelected: () {
          _doubleTapAt = d.localPosition;
          _addKeyAt(width);
        },
      ),
      MenuItem(
        'Delete ${lane.label} track',
        danger: true,
        onSelected: () =>
            editor.deleteTrack(motion, lane.group.name, lane.prop),
      ),
      MenuItem(
        'Delete ${lane.group.name}',
        danger: true,
        onSelected: () => editor.deleteGroup(motion, lane.group.name),
      ),
    ]);
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
          // From the down point: the double-tap recognizer beside this one
          // holds the arena for its slop, and a drag that started counting
          // only after would lose that distance.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragDown: (d) => _down(d.localPosition, width),
          onHorizontalDragUpdate: (d) => _update(d.delta.dx, width),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          // A double-click on the lane is a new key there.
          onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
          onDoubleTap: () => _addKeyAt(width),
          onSecondaryTapUp: (d) => _contextMenu(context, d, width),
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
  Widget build(BuildContext context) => SceneShortcutScope(
    focusNode: focusNode,
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
    child: child,
  );
}
