import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/stage.dart';
import '../../ui/tappable.dart';
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
    required this.content,
    this.status,
    this.trailing = const [],
  });

  final SceneEditor editor;

  /// The picture, sized to the artboard.
  final Widget content;

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
                return ClipRect(
                  child: InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(3000),
                    minScale: 0.1,
                    maxScale: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(_margin),
                      child: _artboard(),
                    ),
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
      child: Row(
        spacing: FwSpacing.md,
        children: [
          AnimatedBuilder(
            animation: doc.listenable,
            builder: (context, _) => Text(
              '${_artboardWidth.round()} × ${_artboardHeight.round()}',
              style: context.type.mono.copyWith(color: colors.mut),
            ),
          ),
          if (widget.status case var status?)
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
              '${(_transform.value.getMaxScaleOnAxis() * 100).round()}%',
              style: context.type.mono.copyWith(color: colors.mut2),
            ),
          ),
          ...widget.trailing,
        ],
      ),
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
            widget.content,
            AnimatedBuilder(
              animation: geometry,
              builder: (context, _) => _HitLayer(editor),
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

/// Everything the mouse can do to the artboard, as transparent widgets over
/// the renderer: a marquee on the empty ground, a target per addressable
/// node, and the selection painted on top.
class _HitLayer extends StatefulWidget {
  const _HitLayer(this.editor);

  final SceneEditor editor;

  @override
  State<_HitLayer> createState() => _HitLayerState();
}

class _HitLayerState extends State<_HitLayer> {
  Offset? _marqueeStart;
  Rect? _marquee;

  SceneEditor get editor => widget.editor;

  void _updateMarquee(Offset at) {
    var rect = Rect.fromPoints(_marqueeStart!, at);
    setState(() => _marquee = rect);
    editor.selectWithin(rect.scene);
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => editor.clearSelection(),
              onPanStart: (d) {
                _marqueeStart = d.localPosition;
                _updateMarquee(d.localPosition);
              },
              onPanUpdate: (d) => _updateMarquee(d.localPosition),
              onPanEnd: (_) => setState(() {
                _marqueeStart = null;
                _marquee = null;
              }),
            ),
          ),
          for (var node in editor.addressable())
            if (node.measured != null)
              Positioned.fromRect(
                rect: node.measured!.flutter,
                child: _NodeTarget(
                  editor,
                  node,
                  key: ValueKey('node:${node.name}'),
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
  const _NodeTarget(this.editor, this.node, {super.key});

  final SceneEditor editor;
  final SceneNode node;

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
        onTapDown: (_) => editor.select(node, toggle: toggleModifier),
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
