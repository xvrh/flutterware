// Disposable spike: an interactive scene canvas over the uniform-node model.
// Tree panel + zoomable canvas (select, drag, resize) + inspector. Exists to
// produce findings about the model, not to be shipped.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../src/scene/editor.dart';
import '../src/scene/ui/inspector.dart';
import '../src/scene/ui/modifiers.dart';
import '../src/scene/ui/shortcuts.dart';
import 'drafts.dart';
import 'remote.dart';

/// The toy's own measurement anchors — the core model carries no widget
/// keys, so the local mirror keys nodes itself, the way the guest does.
final _nodeKeys = Expando<GlobalKey>();

GlobalKey _nodeKey(SceneNode node) => _nodeKeys[node] ??= GlobalKey();

void main() {
  runApp(const CanvasToyApp());
}

class CanvasToyApp extends StatefulWidget {
  const CanvasToyApp({super.key});

  @override
  State<CanvasToyApp> createState() => _CanvasToyAppState();
}

class _CanvasToyAppState extends State<CanvasToyApp> {
  final doc = coffeeBannerDraft();
  late final editor = SceneEditor(doc);
  late final link = RemoteSceneLink(doc, editor: editor);

  @override
  void initState() {
    super.initState();
    installSceneFrameFlush();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Canvas toy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A64D0)),
        visualDensity: VisualDensity.compact,
      ),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MotionTransport(doc, coffeeIntroDraft()),
            const Divider(height: 1),
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  doc.listenable,
                  editor.listenable,
                ]),
                builder: (context, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tree and canvas share the editing focus scope; the
                    // inspector stays OUTSIDE it, so its text fields keep
                    // every key to themselves — a Backspace in a field must
                    // never delete a node.
                    Expanded(
                      child: EditorShortcuts(
                        editor,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 230, child: TreePanel(editor)),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: CanvasArea(editor, status: link.status),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 290, child: SceneInspector(editor)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MotionTransport extends StatefulWidget {
  const MotionTransport(this.doc, this.motion, {super.key});

  final SceneDocument doc;
  final MotionDocument motion;

  @override
  State<MotionTransport> createState() => _MotionTransportState();
}

class _MotionTransportState extends State<MotionTransport>
    with SingleTickerProviderStateMixin {
  late final _bound = BoundMotion.bind(widget.motion, widget.doc);
  late final _player = MotionPlayer(_bound, vsync: this);
  static const _rates = [0.5, 1.0, 2.0];

  @override
  void initState() {
    super.initState();
    installSceneFrameFlush();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds ride the document's own flush: a playing motion notifies
    // once per frame, which is exactly the scrubber's clock.
    return AnimatedBuilder(
      animation: widget.doc.listenable,
      builder: (context, _) {
        var playing = _player.status == MotionPlayerStatus.playing;
        var total = _bound.duration.inMilliseconds;
        var at = _player.position.inMilliseconds.clamp(0, total);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: () =>
                    setState(playing ? _player.pause : _player.play),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.stop),
                tooltip: 'Stop (drops the fx, the scene is untouched)',
                onPressed: () => setState(_player.stop),
              ),
              Expanded(
                child: Slider(
                  value: at.toDouble(),
                  max: total.toDouble(),
                  onChanged: (v) => setState(
                    () => _player.seek(Duration(milliseconds: v.round())),
                  ),
                ),
              ),
              Text(
                '${(at / 1000).toStringAsFixed(2)}s / '
                '${(total / 1000).toStringAsFixed(2)}s',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              TextButton(
                onPressed: () => setState(() {
                  var i = _rates.indexOf(_player.rate);
                  _player.rate = _rates[(i + 1) % _rates.length];
                }),
                child: Text(
                  '${_player.rate}x',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tree panel
// ---------------------------------------------------------------------------

class TreePanel extends StatelessWidget {
  const TreePanel(this.editor, {super.key});

  final SceneEditor editor;

  SceneDocument get doc => editor.doc;

  @override
  Widget build(BuildContext context) {
    var rows = doc.walk().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _AddButton(
                'Text',
                () => _add(TextNode(doc.uniqueName('text'), 'Text')),
              ),
              _AddButton(
                'Shape',
                () => _add(
                  ShapeNode(doc.uniqueName('shape'))
                    ..width = 80
                    ..height = 80
                    ..fill = const SceneColor(0xFF888888),
                ),
              ),
              _AddButton(
                'Frame',
                () => _add(
                  FrameNode(doc.uniqueName('frame'))
                    ..width = 200
                    ..height = 120,
                ),
              ),
              _AddButton('100', _stress),
              IconButton(
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: _selectedIndex == null ? null : () => _reorder(-1),
              ),
              IconButton(
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward, size: 16),
                onPressed: _selectedIndex == null ? null : () => _reorder(1),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: editor.selectedNodes.isEmpty
                    ? null
                    : editor.deleteSelection,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: [
              for (var (node, depth) in rows)
                InkWell(
                  onTap: () {
                    editor.select(
                      node == doc.root ? null : node,
                      toggle: toggleModifier,
                    );
                  },
                  child: Container(
                    color: editor.isSelected(node)
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    padding: EdgeInsets.only(
                      left: 8.0 + depth * 14,
                      top: 5,
                      bottom: 5,
                    ),
                    child: Row(
                      children: [
                        Icon(_iconFor(node), size: 13),
                        const SizedBox(width: 6),
                        Text(
                          node.name,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  int? get _selectedIndex {
    var node = editor.single;
    if (node == null) return null;
    return doc.parentOf(node)?.children.indexOf(node);
  }

  void _reorder(int delta) {
    var node = editor.single;
    var index = _selectedIndex;
    if (node == null || index == null) return;
    editor.perform('Reorder ${node.name}', () {
      var parent = doc.parentOf(node)!;
      var clamped = (index + delta).clamp(0, parent.children.length - 1);
      parent.children
        ..removeAt(index)
        ..insert(clamped, node);
    });
  }

  /// Scale probe: each press adds a frame of 100 nodes (dots and tiny
  /// texts), so payload, sweep and both renderers grow together.
  void _stress() {
    var k = doc.root.children.where((n) => n.name.startsWith('stress')).length;
    var frame = FrameNode('stress$k')
      ..x = 20
      ..y = 20.0 + 56 * k
      ..width = 984
      ..height = 52;
    for (var i = 0; i < 100; i++) {
      var col = i % 25;
      var row = i ~/ 25;
      var node = i.isEven
          ? (ShapeNode('s${k}x$i', circle: true)
                  ..width = 8
                  ..height = 8
                  ..fill = SceneColor(
                    0xFF000000 | (90 + i) << 16 | 130 << 8 | (220 - i),
                  ))
                as SceneNode
          : (TextNode('t${k}x$i', '$i')
              ..fontSize = 9
              ..color = const SceneColor(0xB3FFFFFF));
      node
        ..x = col * 39.0
        ..y = row * 13.0;
      frame.children.add(node);
    }
    editor.perform('Add stress frame', () => doc.root.children.add(frame));
  }

  void _add(SceneNode node) {
    var target = switch (editor.primary) {
      FrameNode f => f,
      SceneNode n => doc.parentOf(n) ?? doc.root,
      null => doc.root,
    };
    editor.perform('Add ${node.name}', () => target.children.add(node));
    editor.select(node);
  }

  IconData _iconFor(SceneNode node) => switch (node) {
    FrameNode() => Icons.crop_square,
    TextNode() => Icons.text_fields,
    ShapeNode() => Icons.circle_outlined,
    ExternalNode() => Icons.extension_outlined,
  };
}

class _AddButton extends StatelessWidget {
  const _AddButton(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
      ),
      onPressed: onTap,
      child: Text('+ $label', style: const TextStyle(fontSize: 11)),
    );
  }
}

// ---------------------------------------------------------------------------
// Canvas
// ---------------------------------------------------------------------------

class CanvasArea extends StatefulWidget {
  const CanvasArea(this.editor, {super.key, this.status, this.canvasContent});

  final SceneEditor editor;
  final ValueListenable<String>? status;

  /// Replaces the local mirror ([NodeView] of the root) as the artboard's
  /// picture — the composited spike mounts the guest's texture here. The hit
  /// layer, selection overlay and resize handle stay on top either way; with
  /// no local scene mounted, measured rects come from the guest.
  final Widget? canvasContent;

  @override
  State<CanvasArea> createState() => _CanvasAreaState();
}

class _CanvasAreaState extends State<CanvasArea> {
  final transform = TransformationController();
  var _fitted = false;
  Size _viewport = const Size(800, 600);

  SceneEditor get editor => widget.editor;
  SceneDocument get doc => widget.editor.doc;

  @override
  Widget build(BuildContext context) {
    _scheduleSweep();
    return Container(
      color: const Color(0xFF3A3D42),
      child: Column(
        children: [
          _toolbar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = constraints.biggest;
                if (!_fitted) {
                  _fitted = true;
                  _fit();
                }
                return InteractiveViewer(
                  transformationController: transform,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(3000),
                  minScale: 0.1,
                  maxScale: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(600),
                    child: _artboard(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      color: const Color(0xFF2C2E33),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text(
            '${doc.root.width!.round()} × ${doc.root.height!.round()}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 16),
          if (widget.status != null)
            ValueListenableBuilder<String>(
              valueListenable: widget.status!,
              builder: (context, value, _) => Text(
                value,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: _fit,
            child: const Text('Fit', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => _setScale(1),
            child: const Text('100%', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _fit() {
    var w = doc.root.width ?? 1024;
    var h = doc.root.height ?? 500;
    var scale = ((_viewport.width - 80) / w).clamp(
      0.05,
      ((_viewport.height - 80) / h).clamp(0.05, 2.0),
    );
    _setScale(scale);
  }

  /// The artboard's top-left sits at (600, 600) in child coordinates — the
  /// canvas padding. Centers the artboard in the viewport at [scale].
  void _setScale(double scale) {
    var w = doc.root.width ?? 1024;
    var h = doc.root.height ?? 500;
    var tx = _viewport.width / 2 - scale * (600 + w / 2);
    var ty = _viewport.height / 2 - scale * (600 + h / 2);
    var m = Matrix4.identity();
    m.setEntry(0, 0, scale);
    m.setEntry(1, 1, scale);
    m.setEntry(0, 3, tx);
    m.setEntry(1, 3, ty);
    transform.value = m;
  }

  Widget _artboard() {
    return SizedBox(
      width: doc.root.width,
      height: doc.root.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.canvasContent ?? NodeView(doc.root),
          AnimatedBuilder(
            animation: Listenable.merge([
              doc.geometryEpoch.listenable,
              editor.listenable,
            ]),
            builder: (context, _) => _HitLayer(editor),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([
              doc.geometryEpoch.listenable,
              editor.listenable,
            ]),
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
    );
  }

  void _scheduleSweep() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var rootBox =
          _nodeKey(doc.root).currentContext?.findRenderObject() as RenderBox?;
      if (rootBox == null) return;
      var changed = false;
      for (var (node, _) in doc.walk()) {
        var box =
            _nodeKey(node).currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        var topLeft = box.localToGlobal(Offset.zero, ancestor: rootBox);
        var rect = (topLeft & box.size).scene;
        if (node.measured != rect) {
          node.measured = rect;
          changed = true;
        }
      }
      if (changed) doc.geometryEpoch.value++;
    });
  }
}

/// Renders one node (and its subtree) with the uniform styling bag applied.
class NodeView extends StatelessWidget {
  const NodeView(this.node, {super.key});

  final SceneNode node;

  @override
  Widget build(BuildContext context) {
    Widget? inner;
    switch (node) {
      case TextNode t:
        inner = Text(
          t.text,
          style: TextStyle(
            fontSize: t.fxRendered('fontSize') as double,
            fontWeight: t.weight.flutter,
            color: (t.fxRendered('color') as SceneColor).flutter,
            height: 1.15,
          ),
        );
      case ShapeNode _:
        inner = null;
      case ExternalNode e:
        // The editor's mirror cannot render a widget it never compiled
        // against — the guest does. Here, a labeled placeholder.
        inner = Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0x224A64D0),
            border: Border.all(color: const Color(0x664A64D0)),
          ),
          child: Text(
            '⟪${e.entry}⟫',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8FA0E8)),
          ),
        );
      case FrameNode f:
        var children = [for (var c in f.children) _positioned(c)];
        inner = switch (f.layout) {
          NodeLayout.absolute => Stack(
            clipBehavior: Clip.none,
            children: children,
          ),
          NodeLayout.row => Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: f.mainAlign.flutter,
            crossAxisAlignment: f.crossAlign.flutter,
            spacing: f.fxRendered('gap') as double,
            children: children,
          ),
          NodeLayout.column => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: f.mainAlign.flutter,
            crossAxisAlignment: f.crossAlign.flutter,
            spacing: f.fxRendered('gap') as double,
            children: children,
          ),
        };
    }

    var shape = node is ShapeNode && (node as ShapeNode).circle;
    // The mirror draws the RENDERED plane — base op fx — so a playing
    // motion and an app effect are visible here exactly as in the guest.
    var fill = node.hasFx('fill')
        ? node.fxRendered('fill') as SceneColor
        : node.fill;
    Widget result = Container(
      key: _nodeKey(node),
      width: node.width,
      height: node.height,
      padding: node is FrameNode && (node as FrameNode).padding > 0
          ? EdgeInsets.symmetric(
              horizontal: (node as FrameNode).padding,
              vertical: (node as FrameNode).padding * 0.6,
            )
          : null,
      decoration: fill != null || node.cornerRadius > 0
          ? BoxDecoration(
              color: fill?.flutter,
              shape: shape ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: shape || node.cornerRadius == 0
                  ? null
                  : BorderRadius.circular(node.cornerRadius),
            )
          : null,
      child: inner,
    );
    var opacity = (node.fxRendered('opacity') as double).clamp(0.0, 1.0);
    if (opacity < 1) {
      result = Opacity(opacity: opacity, child: result);
    }
    var tx = node.fxRendered('translateX') as double;
    var ty = node.fxRendered('translateY') as double;
    var scale = node.fxRendered('scale') as double;
    var rotate = node.fxRendered('rotate') as double;
    if (tx != 0 || ty != 0 || scale != 1 || rotate != 0) {
      var m = Matrix4.translationValues(tx, ty, 0);
      if (rotate != 0) m.rotateZ(rotate * math.pi / 180);
      if (scale != 1) m.multiply(Matrix4.diagonal3Values(scale, scale, 1));
      result = Transform(
        alignment: Alignment.center,
        transform: m,
        child: result,
      );
    }
    return result;
  }

  Widget _positioned(SceneNode child) {
    var frame = node as FrameNode;
    var view = NodeView(child);
    if (frame.layout == NodeLayout.absolute) {
      return Positioned(left: child.x, top: child.y, child: view);
    }
    return view;
  }
}

/// One transparent hit target per addressable node, placed from its measured
/// rect, under the selection/hover/marquee paint. Selection changes the
/// addressable set, so the click ladder is plain z-order — no coordinate
/// math anywhere in the editor. Dragging empty canvas is the marquee: nodes
/// whose measured rect intersects it become the selection, live.
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
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Below every node target: empty-canvas clicks deselect, and an
          // empty-canvas drag is the marquee.
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
                painter: _SelectionPainter(editor, marquee: _marquee),
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

  // A drive-layer drag can be down → one large move → up: the pan recognizer
  // accepts on that single move, so panStart's displacement from the down
  // point is already most of the drag and panUpdate may never fire. A fast
  // human flick does the same. So panStart applies its own displacement.
  void _apply(Offset localPosition, Offset delta) {
    var parent = doc.parentOf(node);
    if (parent == null) return;
    if (parent.layout == NodeLayout.absolute) {
      // Dragging any selected node moves the whole selection.
      editor.nudgeSelection(delta.dx, delta.dy, mergeKey: 'drag');
    } else {
      // Flex parent: a drag is a reorder, not a move. Position in artboard
      // coords = target origin + local offset.
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
        // The gesture's undo entry closes here, so the next drag is its own.
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
    return GestureDetector(
      onPanDown: (d) => _downLocal = d.localPosition,
      onPanStart: (d) => _apply(d.localPosition - _downLocal),
      onPanUpdate: (d) => _apply(d.delta),
      onPanEnd: (_) => widget.editor.endMerge(),
      onPanCancel: widget.editor.endMerge,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFF4A64D0), width: 2),
        ),
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.editor, {this.marquee});

  final SceneEditor editor;
  final Rect? marquee;

  @override
  void paint(Canvas canvas, Size size) {
    var stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF4A64D0);
    // Hover first, under the selection strokes.
    if (editor.hover case var name?
        when !editor.selectedNodes.any((n) => n.name == name)) {
      var rect = editor.doc.nodeNamed(name)?.measured;
      if (rect != null) {
        canvas.drawRect(
          rect.flutter,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x804A64D0),
        );
      }
    }
    for (var node in editor.selectedNodes) {
      var rect = node.measured;
      if (rect != null) canvas.drawRect(rect.flutter, stroke);
    }
    if (marquee case var rect?) {
      canvas.drawRect(rect, Paint()..color = const Color(0x184A64D0));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xB34A64D0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) => true;
}
