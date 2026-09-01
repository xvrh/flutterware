// Disposable spike: an interactive scene canvas over the uniform-node model.
// Tree panel + zoomable canvas (select, drag, resize) + inspector. Exists to
// produce findings about the model, not to be shipped.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'model.dart';
import 'motion_model.dart';
import 'motion_runtime.dart';
import 'remote.dart';

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
  late final link = RemoteSceneLink(doc);

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
                animation: doc,
                builder: (context, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 230, child: TreePanel(doc)),
                    const VerticalDivider(width: 1),
                    Expanded(child: CanvasArea(doc, status: link.status)),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 290, child: InspectorPanel(doc)),
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

/// Play controls for one motion over the toy's document: bind, play, pause,
/// stop, scrub, rate. The player is the applicator — every frame it writes
/// the fx plane and the coalesced flush repaints whatever is watching the
/// document, the local mirror and the guest wire alike.
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
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds ride the document's own flush: a playing motion notifies
    // once per frame, which is exactly the scrubber's clock.
    return AnimatedBuilder(
      animation: widget.doc,
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
  const TreePanel(this.doc, {super.key});

  final SceneDocument doc;

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
                    ..fill = const Color(0xFF888888),
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
                onPressed: _selectedIndex == null
                    ? null
                    : () => doc.reorder(doc.selected!, _selectedIndex! - 1),
              ),
              IconButton(
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward, size: 16),
                onPressed: _selectedIndex == null
                    ? null
                    : () => doc.reorder(doc.selected!, _selectedIndex! + 1),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: doc.selected == null
                    ? null
                    : () => doc.delete(doc.selected!),
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
                  onTap: () => doc.select(node == doc.root ? null : node),
                  child: Container(
                    color: doc.selected == node
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
    var node = doc.selected;
    if (node == null) return null;
    return doc.parentOf(node)?.children.indexOf(node);
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
                  ..fill = Color.fromARGB(255, 90 + i, 130, 220 - i))
                as SceneNode
          : (TextNode('t${k}x$i', '$i')
              ..fontSize = 9
              ..color = const Color(0xB3FFFFFF));
      node
        ..x = col * 39.0
        ..y = row * 13.0;
      frame.children.add(node);
    }
    doc.edit(() => doc.root.children.add(frame));
  }

  void _add(SceneNode node) {
    var target = switch (doc.selected) {
      FrameNode f => f,
      SceneNode n => doc.parentOf(n) ?? doc.root,
      null => doc.root,
    };
    doc.edit(() => target.children.add(node));
    doc.select(node);
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
  const CanvasArea(this.doc, {super.key, this.status, this.canvasContent});

  final SceneDocument doc;
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

  SceneDocument get doc => widget.doc;

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
          ValueListenableBuilder(
            valueListenable: doc.geometryEpoch,
            builder: (context, _, _) => _HitLayer(doc),
          ),
          ValueListenableBuilder(
            valueListenable: doc.geometryEpoch,
            builder: (context, _, _) => Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SelectionPainter(doc)),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: doc.geometryEpoch,
            builder: (context, _, _) {
              var rect = doc.selected?.measured;
              if (rect == null) return const SizedBox();
              return Positioned(
                left: rect.right - 6,
                top: rect.bottom - 6,
                child: _ResizeHandle(doc),
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
          doc.root.key.currentContext?.findRenderObject() as RenderBox?;
      if (rootBox == null) return;
      var changed = false;
      for (var (node, _) in doc.walk()) {
        var box = node.key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        var topLeft = box.localToGlobal(Offset.zero, ancestor: rootBox);
        var rect = topLeft & box.size;
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
            fontWeight: t.weight,
            color: t.fxRendered('color') as Color,
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
            mainAxisAlignment: f.mainAlign,
            crossAxisAlignment: f.crossAlign,
            spacing: f.fxRendered('gap') as double,
            children: children,
          ),
          NodeLayout.column => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: f.mainAlign,
            crossAxisAlignment: f.crossAlign,
            spacing: f.fxRendered('gap') as double,
            children: children,
          ),
        };
    }

    var shape = node is ShapeNode && (node as ShapeNode).circle;
    // The mirror draws the RENDERED plane — base op fx — so a playing
    // motion and an app effect are visible here exactly as in the guest.
    var fill = node.hasFx('fill')
        ? node.fxRendered('fill') as Color
        : node.fill;
    Widget result = Container(
      key: node.key,
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
              color: fill,
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
/// rect. Selection changes the addressable set, so the click ladder is plain
/// z-order — no coordinate math anywhere in the editor.
class _HitLayer extends StatelessWidget {
  const _HitLayer(this.doc);

  final SceneDocument doc;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Below every node target: empty-canvas clicks deselect.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => doc.select(null),
            ),
          ),
          for (var node in doc.addressable())
            if (node.measured != null)
              Positioned.fromRect(
                rect: node.measured!,
                child: _NodeTarget(
                  doc,
                  node,
                  key: ValueKey('node:${node.name}'),
                ),
              ),
        ],
      ),
    );
  }
}

class _NodeTarget extends StatefulWidget {
  const _NodeTarget(this.doc, this.node, {super.key});

  final SceneDocument doc;
  final SceneNode node;

  @override
  State<_NodeTarget> createState() => _NodeTargetState();
}

class _NodeTargetState extends State<_NodeTarget> {
  var _downLocal = Offset.zero;

  SceneDocument get doc => widget.doc;
  SceneNode get node => widget.node;

  // A drive-layer drag can be down → one large move → up: the pan recognizer
  // accepts on that single move, so panStart's displacement from the down
  // point is already most of the drag and panUpdate may never fire. A fast
  // human flick does the same. So panStart applies its own displacement.
  void _apply(Offset localPosition, Offset delta) {
    var parent = doc.parentOf(node);
    if (parent == null) return;
    if (parent.layout == NodeLayout.absolute) {
      doc.edit(() {
        node.x += delta.dx;
        node.y += delta.dy;
      });
    } else {
      // Flex parent: a drag is a reorder, not a move. Position in artboard
      // coords = target origin + local offset.
      var p = (node.measured?.topLeft ?? Offset.zero) + localPosition;
      var main = parent.layout == NodeLayout.row ? p.dx : p.dy;
      var index = 0;
      for (var sibling in parent.children) {
        if (sibling == node) continue;
        var rect = sibling.measured;
        if (rect == null) continue;
        var center = parent.layout == NodeLayout.row
            ? rect.center.dx
            : rect.center.dy;
        if (main > center) index++;
      }
      doc.reorder(node, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => doc.select(node),
      onPanDown: (d) => _downLocal = d.localPosition,
      onPanStart: (d) {
        doc.select(node);
        _apply(d.localPosition, d.localPosition - _downLocal);
      },
      onPanUpdate: (d) => _apply(d.localPosition, d.delta),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle(this.doc);

  final SceneDocument doc;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  var _downLocal = Offset.zero;

  void _apply(Offset delta) {
    var node = widget.doc.selected;
    if (node == null) return;
    widget.doc.edit(() {
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
  _SelectionPainter(this.doc);

  final SceneDocument doc;

  @override
  void paint(Canvas canvas, Size size) {
    var rect = doc.selected?.measured;
    if (rect == null) return;
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF4A64D0);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Inspector
// ---------------------------------------------------------------------------

const _palette = [
  null,
  Colors.white,
  Color(0xFF1A1A1A),
  Color(0xFF2B1B12),
  Color(0xFF4A2F1F),
  Color(0xFF6B4226),
  Color(0xFFD8C9BD),
  Color(0xFFE8632B),
  Color(0xFFF2B705),
  Color(0xFF3E7C4F),
  Color(0xFF4A64D0),
];

class InspectorPanel extends StatelessWidget {
  const InspectorPanel(this.doc, {super.key});

  final SceneDocument doc;

  @override
  Widget build(BuildContext context) {
    var node = doc.selected ?? doc.root;
    var parent = node == doc.root ? null : doc.parentOf(node);
    var inFlex = parent != null && parent.layout != NodeLayout.absolute;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          '${node.typeName} · ${node.name}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (inFlex)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Position measured by parent layout',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: NumField(
                'X',
                node.x,
                enabled: !inFlex && node != doc.root,
                onChanged: (v) => doc.edit(() => node.x = v ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                'Y',
                node.y,
                enabled: !inFlex && node != doc.root,
                onChanged: (v) => doc.edit(() => node.y = v ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: NumField(
                'W',
                node.width,
                nullable: true,
                hint: 'hug',
                onChanged: (v) => doc.edit(() => node.width = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                'H',
                node.height,
                nullable: true,
                hint: 'hug',
                onChanged: (v) => doc.edit(() => node.height = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _label('Fill'),
        _swatches(node.fill, (c) => doc.edit(() => node.fill = c)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: NumField(
                'Corner',
                node.cornerRadius,
                onChanged: (v) => doc.edit(() => node.cornerRadius = v ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                'Opacity',
                node.opacity,
                onChanged: (v) =>
                    doc.edit(() => node.opacity = (v ?? 1).clamp(0, 1)),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        ...switch (node) {
          TextNode t => _textProps(t),
          FrameNode f => _frameProps(f),
          ShapeNode s => _shapeProps(s),
          ExternalNode e => _extProps(e),
        },
      ],
    );
  }

  List<Widget> _textProps(TextNode t) {
    return [
      _label('Content'),
      TextFormField(
        key: ValueKey(t),
        initialValue: t.text,
        style: const TextStyle(fontSize: 12),
        maxLines: 3,
        minLines: 1,
        onChanged: (v) => doc.edit(() => t.text = v),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: NumField(
              'Size',
              t.fontSize,
              onChanged: (v) => doc.edit(() => t.fontSize = v ?? 14),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<FontWeight>(
              initialValue: t.weight,
              decoration: const InputDecoration(
                labelText: 'Weight',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: const [
                DropdownMenuItem(
                  value: FontWeight.w400,
                  child: Text('Regular'),
                ),
                DropdownMenuItem(value: FontWeight.w500, child: Text('Medium')),
                DropdownMenuItem(
                  value: FontWeight.w600,
                  child: Text('Semibold'),
                ),
                DropdownMenuItem(value: FontWeight.w700, child: Text('Bold')),
                DropdownMenuItem(value: FontWeight.w900, child: Text('Black')),
              ],
              onChanged: (v) => doc.edit(() => t.weight = v ?? FontWeight.w400),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _label('Color'),
      _swatches(t.color, (c) => doc.edit(() => t.color = c ?? Colors.black)),
    ];
  }

  List<Widget> _frameProps(FrameNode f) {
    return [
      _label('Layout'),
      SegmentedButton<NodeLayout>(
        segments: const [
          ButtonSegment(value: NodeLayout.absolute, label: Text('Free')),
          ButtonSegment(value: NodeLayout.row, label: Text('Row')),
          ButtonSegment(value: NodeLayout.column, label: Text('Col')),
        ],
        selected: {f.layout},
        // A layout-mode switch is a geometry transaction, not a flag flip:
        // entering Free bakes each child's measured position into authored
        // x/y; entering flex re-derives order from visual position.
        onSelectionChanged: (s) => doc.edit(() {
          var next = s.first;
          var origin = f.measured?.topLeft ?? Offset.zero;
          if (next == NodeLayout.absolute) {
            for (var c in f.children) {
              var rect = c.measured;
              if (rect != null) {
                c.x = rect.left - origin.dx;
                c.y = rect.top - origin.dy;
              }
            }
          } else {
            f.children.sort((a, b) {
              var ra = a.measured, rb = b.measured;
              if (ra == null || rb == null) return 0;
              return next == NodeLayout.row
                  ? ra.left.compareTo(rb.left)
                  : ra.top.compareTo(rb.top);
            });
          }
          f.layout = next;
        }),
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: NumField(
              'Gap',
              f.gap,
              onChanged: (v) => doc.edit(() => f.gap = v ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NumField(
              'Padding',
              f.padding,
              onChanged: (v) => doc.edit(() => f.padding = v ?? 0),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (f.layout != NodeLayout.absolute)
        DropdownButtonFormField<CrossAxisAlignment>(
          initialValue: f.crossAlign,
          decoration: const InputDecoration(
            labelText: 'Cross align',
            isDense: true,
          ),
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          items: const [
            DropdownMenuItem(
              value: CrossAxisAlignment.start,
              child: Text('Start'),
            ),
            DropdownMenuItem(
              value: CrossAxisAlignment.center,
              child: Text('Center'),
            ),
            DropdownMenuItem(value: CrossAxisAlignment.end, child: Text('End')),
            DropdownMenuItem(
              value: CrossAxisAlignment.stretch,
              child: Text('Stretch'),
            ),
          ],
          onChanged: (v) =>
              doc.edit(() => f.crossAlign = v ?? CrossAxisAlignment.center),
        ),
    ];
  }

  List<Widget> _extProps(ExternalNode e) {
    return [
      _label('Entry'),
      Text(e.entry, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      for (var arg in e.args.entries) ...[
        if (arg.value case num number)
          NumField(
            arg.key,
            number.toDouble(),
            onChanged: (v) => doc.edit(() => e.args[arg.key] = v),
          )
        else
          TextFormField(
            key: ValueKey('${e.name}:${arg.key}'),
            initialValue: '${arg.value}',
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(labelText: arg.key, isDense: true),
            onChanged: (v) => doc.edit(() => e.args[arg.key] = v),
          ),
        const SizedBox(height: 8),
      ],
    ];
  }

  List<Widget> _shapeProps(ShapeNode s) {
    return [
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Circle', style: TextStyle(fontSize: 12)),
        value: s.circle,
        onChanged: (v) => doc.edit(() => s.circle = v),
      ),
    ];
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  );

  Widget _swatches(Color? current, void Function(Color?) onPick) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var color in _palette)
          InkWell(
            onTap: () => onPick(color),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: current == color
                      ? const Color(0xFF4A64D0)
                      : Colors.black26,
                  width: current == color ? 2 : 1,
                ),
              ),
              child: color == null
                  ? const Icon(Icons.block, size: 14, color: Colors.black38)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// A number field that commits on submit or focus loss. Blank commits null
/// when [nullable] (spelled "hug" in the UI).
class NumField extends StatefulWidget {
  const NumField(
    this.label,
    this.value, {
    super.key,
    required this.onChanged,
    this.nullable = false,
    this.enabled = true,
    this.hint,
  });

  final String label;
  final double? value;
  final void Function(double?) onChanged;
  final bool nullable;
  final bool enabled;
  final String? hint;

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final controller = TextEditingController(text: _format(widget.value));
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !focus.hasFocus) {
      controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  String _format(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  }

  void _commit() {
    var text = controller.text.trim();
    if (text.isEmpty) {
      widget.onChanged(widget.nullable ? null : 0);
      return;
    }
    var parsed = double.tryParse(text);
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focus,
      enabled: widget.enabled,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        isDense: true,
      ),
      // Live commit: the canvas is the feedback, so a parseable keystroke
      // lands immediately. Blank (→ null/hug) waits for blur or submit.
      onChanged: (v) {
        var parsed = double.tryParse(v.trim());
        if (parsed != null) widget.onChanged(parsed);
      },
      onSubmitted: (_) => _commit(),
    );
  }
}
