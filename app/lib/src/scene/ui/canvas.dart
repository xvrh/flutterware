import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/stage.dart';
import '../../ui/tappable.dart';
import '../../ui/zoomable_canvas.dart';
import 'pointer.dart';
import '../editor.dart';
import 'modifiers.dart';

/// The artboard on a zoomable ground, with the editor's hit layer over it.
///
/// The canvas draws nothing of the scene itself: [content] is the renderer —
/// the guest's texture in the studio, a `SceneView` in a demo — and what the
/// hit layer knows about geometry is whatever that renderer measured onto the
/// nodes. Selection, hover, marquee, drag and resize are all here, all over
/// `SceneEditor`, so the two renderers behave identically to the mouse.
class SceneCanvas extends StatefulWidget {
  const SceneCanvas(
    this.editor, {
    super.key,
    this.content,
    this.pane,
    this.status,
    this.trailing = const [],
    this.onEnterNested,
  });

  final SceneEditor editor;

  /// Double-clicking a nested scene's box drills into it.
  final ValueChanged<SceneNode>? onEnterNested;

  /// The picture, sized to the artboard and zoomed with it — a `SceneView`
  /// rendered in this process. Magnified, it magnifies.
  final Widget? content;

  /// The picture as a layer the size of the pane, under the artboard, given
  /// the artboard-to-pane matrix and the pane's size — for a guest that
  /// renders through the view itself, so a magnified artboard is rasterised
  /// at its magnification. Whichever of the two the host has; both is odd.
  final Widget Function(BuildContext context, Matrix4 view, Size pane)? pane;

  /// What the renderer is doing, for the toolbar — the guest booting, a
  /// frame's cost.
  final ValueListenable<String>? status;

  /// Controls an arrangement wants on the canvas toolbar's right.
  final List<Widget> trailing;

  @override
  State<SceneCanvas> createState() => _SceneCanvasState();
}

class _SceneCanvasState extends State<SceneCanvas> {
  final _transform = TransformationController();
  var _fitted = false;
  Size _viewport = const Size(800, 600);

  /// Room around the artboard inside the viewer, so it can be dragged past
  /// the pane's edges in every direction.
  static const _margin = 600.0;

  SceneEditor get editor => widget.editor;
  SceneDocument get doc => widget.editor.doc;

  double get _artboardWidth => doc.root.width ?? 1024;
  double get _artboardHeight => doc.root.height ?? 500;

  /// Artboard to pane: the viewer's transform, with the artboard's margin
  /// inside the viewer's child folded in.
  Matrix4 get _artboardToPane =>
      _transform.value.clone()..translateByDouble(_margin, _margin, 0, 1);

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context),
        Expanded(
          child: StageGround(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = constraints.biggest;
                if (!_fitted) {
                  _fitted = true;
                  // After the frame: setting the transform notifies the
                  // toolbar's readout, which must not happen mid-build.
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fit();
                  });
                }
                // The studio's own pan-and-zoom surface: a two-finger scroll
                // pans, a pinch zooms, ⌘-scroll zooms the browsers' way.
                // A pane layer, when the host draws one, sits under the
                // viewer and is told where the artboard is.
                return ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.pane case var pane?)
                        AnimatedBuilder(
                          animation: _transform,
                          builder: (context, _) =>
                              pane(context, _artboardToPane, _viewport),
                        ),
                      ZoomableCanvas(
                        transformationController: _transform,
                        boundaryMargin: const EdgeInsets.all(3000),
                        minScale: 0.05,
                        maxScale: 64,
                        child: Padding(
                          padding: const EdgeInsets.all(_margin),
                          child: _artboard(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    var colors = context.colors;
    var muted = context.type.caption.copyWith(color: colors.mut2);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      // The tools, the zoom verbs and the readout are the bar; the artboard
      // size and the guest status are the first to go when the pane is
      // narrower than all of it — measured 302px for the lot, and a docked
      // canvas beside a tree and an inspector can be 230.
      child: LayoutBuilder(
        builder: (context, constraints) => _toolbarRow(
          context,
          colors,
          muted,
          roomy: constraints.maxWidth >= 360,
        ),
      ),
    );
  }

  Widget _toolbarRow(
    BuildContext context,
    FwPalette colors,
    TextStyle muted, {
    required bool roomy,
  }) {
    return Row(
      spacing: FwSpacing.md,
      children: [
        AnimatedBuilder(
          animation: editor.listenable,
          builder: (context, _) => Row(
            spacing: FwSpacing.xxs,
            children: [
              for (var (tool, icon, label, key) in const [
                (SceneTool.select, Icons.near_me_outlined, 'Select', 'V'),
                (SceneTool.frame, Icons.crop_square, 'Frame', 'F'),
                (SceneTool.text, Icons.text_fields, 'Text', 'T'),
                (SceneTool.shape, Icons.circle_outlined, 'Shape', 'S'),
              ])
                _Tool(
                  icon: icon,
                  label: label,
                  shortcut: key,
                  active: editor.tool == tool,
                  onTap: () => editor.tool = tool,
                ),
            ],
          ),
        ),
        if (roomy) ...[
          Container(width: 1, height: 16, color: colors.line),
          AnimatedBuilder(
            animation: doc.listenable,
            builder: (context, _) => Text(
              '${_artboardWidth.round()} × ${_artboardHeight.round()}',
              style: context.type.mono.copyWith(color: colors.mut),
            ),
          ),
        ],
        if (widget.status case var status? when roomy)
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (context, value, _) =>
                  Text(value, style: muted, overflow: TextOverflow.ellipsis),
            ),
          )
        else
          const Spacer(),
        _Verb('Fit', _fit),
        _Verb('1:1', () => _setScale(1)),
        AnimatedBuilder(
          animation: _transform,
          builder: (context, _) => Text(
            '${(_transform.value.storage[0] * 100).round()}%',
            style: context.type.mono.copyWith(color: colors.mut2),
          ),
        ),
        ...widget.trailing,
      ],
    );
  }

  void _fit() {
    var scale = ((_viewport.width - 80) / _artboardWidth).clamp(
      0.05,
      ((_viewport.height - 80) / _artboardHeight).clamp(0.05, 2.0),
    );
    _setScale(scale);
  }

  void _setScale(double scale) {
    var tx = _viewport.width / 2 - scale * (_margin + _artboardWidth / 2);
    var ty = _viewport.height / 2 - scale * (_margin + _artboardHeight / 2);
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  Widget _artboard() {
    var geometry = Listenable.merge([
      doc.geometryEpoch.listenable,
      editor.listenable,
    ]);
    return StageEdge(
      child: SizedBox(
        width: _artboardWidth,
        height: _artboardHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ?widget.content,
            AnimatedBuilder(
              animation: geometry,
              builder: (context, _) =>
                  _HitLayer(editor, onEnterNested: widget.onEnterNested),
            ),
            AnimatedBuilder(
              animation: geometry,
              builder: (context, _) {
                var rect = editor.single?.measured;
                if (rect == null) return const SizedBox();
                return Positioned(
                  left: rect.right - 6,
                  top: rect.bottom - 6,
                  child: _ResizeHandle(editor),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Verb extends StatelessWidget {
  const _Verb(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tappable(
    onTap: onTap,
    borderRadius: BorderRadius.circular(context.radii.radiusSmall),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.sm,
        vertical: FwSpacing.xxs,
      ),
      child: Text(label, style: context.type.caption),
    ),
  );
}

/// One of the canvas tools: a glyph, lit when it is the current one.
class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tooltip(
      message: '$label ($shortcut)',
      child: Tappable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
        child: Container(
          padding: const EdgeInsets.all(FwSpacing.xs),
          decoration: BoxDecoration(
            color: active ? colors.accentSoft : null,
            borderRadius: BorderRadius.circular(context.radii.radiusSmall),
          ),
          child: Icon(
            icon,
            size: FwIconSize.md,
            color: active ? colors.accentDark : colors.ink,
          ),
        ),
      ),
    );
  }
}

/// The devices whose press is an edit. A trackpad's two-finger gesture is a
/// pan or a pinch of the canvas and must reach the viewer under these
/// widgets untouched; a recognizer that accepted it turned every scroll over
/// a node into a drag of that node, and over its handle into a resize.
/// Everything the mouse can do to the artboard, as transparent widgets over
/// the renderer: a marquee on the empty ground, a target per addressable
/// node, and the selection painted on top.
class _HitLayer extends StatefulWidget {
  const _HitLayer(this.editor, {this.onEnterNested});

  final SceneEditor editor;
  final ValueChanged<SceneNode>? onEnterNested;

  @override
  State<_HitLayer> createState() => _HitLayerState();
}

class _HitLayerState extends State<_HitLayer> {
  Offset? _marqueeStart;
  Rect? _marquee;

  SceneEditor get editor => widget.editor;
  SceneDocument get doc => widget.editor.doc;

  bool get _drawing => editor.tool != SceneTool.select;

  /// The drag rectangle: a marquee under the select tool, the box of the
  /// node being drawn under the others.
  void _updateMarquee(Offset at) {
    var rect = Rect.fromPoints(_marqueeStart!, at);
    setState(() => _marquee = rect);
    if (!_drawing) editor.selectWithin(rect.scene);
  }

  /// A press with a drawing tool: a drag drew a box, a click a default one.
  void _finishDrawing(Rect? rect, Offset at) {
    var tool = editor.tool;
    var box = rect != null && rect.width > 4 && rect.height > 4
        ? rect
        : Rect.fromLTWH(at.dx, at.dy, 120, 80);
    var node = switch (tool) {
      SceneTool.frame =>
        FrameNode(doc.uniqueName('frame'))
          ..width = _half(box.width)
          ..height = _half(box.height),
      SceneTool.shape =>
        ShapeNode(doc.uniqueName('shape'))
          ..width = _half(box.width)
          ..height = _half(box.height)
          ..fill = const SceneColor(0xFF888888),
      SceneTool.text => TextNode(doc.uniqueName('text'), 'Text'),
      SceneTool.select => null,
    };
    if (node == null) return;
    // A text is placed, not drawn: it hugs its words.
    editor.insertNode(node, x: box.left, y: box.top);
  }

  static double _half(double v) => (v * 2).round() / 2;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: MouseRegion(
              cursor: _drawing ? SystemMouseCursors.precise : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                supportedDevices: editingDevices,
                // A drawn box starts where the mouse went down, not where the
                // recognizer made up its mind: a quick drag would otherwise
                // offset every frame by the slop.
                dragStartBehavior: DragStartBehavior.down,
                onTapDown: (d) {
                  if (_drawing) {
                    _finishDrawing(null, d.localPosition);
                  } else {
                    editor.clearSelection();
                  }
                },
                onPanStart: (d) {
                  _marqueeStart = d.localPosition;
                  _updateMarquee(d.localPosition);
                },
                onPanUpdate: (d) => _updateMarquee(d.localPosition),
                onPanEnd: (d) {
                  var rect = _marquee;
                  var start = _marqueeStart;
                  setState(() {
                    _marqueeStart = null;
                    _marquee = null;
                  });
                  if (_drawing && start != null) _finishDrawing(rect, start);
                },
              ),
            ),
          ),
          // While drawing, the nodes do not take the press: a frame drawn
          // over a headline must not drag the headline.
          if (!_drawing)
            for (var node in editor.addressable())
              if (node.measured != null)
                Positioned.fromRect(
                  rect: node.measured!.flutter,
                  child: _NodeTarget(
                    editor,
                    node,
                    key: ValueKey('node:${node.name}'),
                    onEnterNested: widget.onEnterNested,
                  ),
                ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SelectionPainter(
                  editor,
                  marquee: _marquee,
                  accent: colors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeTarget extends StatefulWidget {
  const _NodeTarget(this.editor, this.node, {super.key, this.onEnterNested});

  final SceneEditor editor;
  final SceneNode node;
  final ValueChanged<SceneNode>? onEnterNested;

  @override
  State<_NodeTarget> createState() => _NodeTargetState();
}

class _NodeTargetState extends State<_NodeTarget> {
  var _downLocal = Offset.zero;

  SceneEditor get editor => widget.editor;
  SceneDocument get doc => widget.editor.doc;
  SceneNode get node => widget.node;

  /// A drag under an absolute parent moves the selection; under a row or a
  /// column it reorders, because there position *is* order.
  void _apply(Offset localPosition, Offset delta) {
    var parent = doc.parentOf(node);
    if (parent == null) return;
    if (parent.layout == NodeLayout.absolute) {
      editor.nudgeSelection(delta.dx, delta.dy, mergeKey: 'drag');
      return;
    }
    var m = node.measured;
    var p = (m == null ? Offset.zero : Offset(m.left, m.top)) + localPosition;
    var main = parent.layout == NodeLayout.row ? p.dx : p.dy;
    var index = 0;
    for (var sibling in parent.children) {
      if (sibling == node) continue;
      var rect = sibling.measured;
      if (rect == null) continue;
      var center = parent.layout == NodeLayout.row
          ? rect.centerX
          : rect.centerY;
      if (main > center) index++;
    }
    var from = parent.children.indexOf(node);
    if (from == index) return;
    editor.perform('Reorder ${node.name}', mergeKey: 'drag', () {
      parent.children
        ..removeAt(from)
        ..insert(index, node);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => editor.hover = node.name,
      onExit: (_) {
        if (editor.hover == node.name) editor.hover = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: editingDevices,
        onTapDown: (_) => editor.select(node, toggle: toggleModifier),
        onDoubleTap: node is SceneRefNode && widget.onEnterNested != null
            ? () => widget.onEnterNested!(node)
            : null,
        onPanDown: (d) => _downLocal = d.localPosition,
        onPanStart: (d) {
          if (!editor.isSelected(node)) editor.select(node);
          _apply(d.localPosition, d.localPosition - _downLocal);
        },
        onPanUpdate: (d) => _apply(d.localPosition, d.delta),
        onPanEnd: (_) => editor.endMerge(),
        onPanCancel: editor.endMerge,
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle(this.editor);

  final SceneEditor editor;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  var _downLocal = Offset.zero;

  void _apply(Offset delta) {
    var node = widget.editor.single;
    if (node == null) return;
    widget.editor.perform('Resize ${node.name}', mergeKey: 'resize', () {
      var rect = node.measured;
      node.width = ((node.width ?? rect?.width ?? 100) + delta.dx).clamp(
        8,
        4000,
      );
      node.height = ((node.height ?? rect?.height ?? 100) + delta.dy).clamp(
        8,
        4000,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        supportedDevices: editingDevices,
        onPanDown: (d) => _downLocal = d.localPosition,
        onPanStart: (d) => _apply(d.localPosition - _downLocal),
        onPanUpdate: (d) => _apply(d.delta),
        onPanEnd: (_) => widget.editor.endMerge(),
        onPanCancel: widget.editor.endMerge,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: colors.panel,
            border: Border.all(color: colors.accent, width: 2),
          ),
        ),
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.editor, {this.marquee, required this.accent});

  final SceneEditor editor;
  final Rect? marquee;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    var stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent;
    if (editor.hover case var name?
        when !editor.selectedNodes.any((n) => n.name == name)) {
      var rect = editor.doc.nodeNamed(name)?.measured;
      if (rect != null) {
        canvas.drawRect(
          rect.flutter,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = accent.withValues(alpha: 0.5),
        );
      }
    }
    for (var node in editor.selectedNodes) {
      var rect = node.measured;
      if (rect != null) canvas.drawRect(rect.flutter, stroke);
    }
    if (marquee case var rect?) {
      canvas.drawRect(rect, Paint()..color = accent.withValues(alpha: 0.1));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) => true;
}
