// Disposable spike: an interactive scene canvas over the uniform-node model.
// Tree panel + zoomable canvas (select, drag, resize) + inspector. Exists to
// produce findings about the model, not to be shipped.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../src/scene/editor.dart';
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
                    SizedBox(width: 290, child: InspectorPanel(editor)),
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

/// The editing focus scope: keyboard verbs for whatever it wraps. Any
/// press inside it takes the keyboard back, a press in the inspector
/// (which is outside) leaves it, and each binding acts on the shared
/// [SceneEditor].
class EditorShortcuts extends StatefulWidget {
  const EditorShortcuts(this.editor, {super.key, required this.child});

  final SceneEditor editor;
  final Widget child;

  @override
  State<EditorShortcuts> createState() => _EditorShortcutsState();
}

class _EditorShortcutsState extends State<EditorShortcuts> {
  // The scope owns its node rather than letting call sites look one up:
  // Focus.of() from a tree row finds whatever Focus happens to be nearest
  // (a Scrollable brings its own), and focusing that does not necessarily
  // take primary focus back from an inspector field — the keys then reach
  // the field's own undo instead, which beeps once it is empty.
  final _node = FocusNode(debugLabel: 'scene editor');

  SceneEditor get editor => widget.editor;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var arrows = <ShortcutActivator, VoidCallback>{};
    for (var (key, dx, dy) in [
      (LogicalKeyboardKey.arrowLeft, -1.0, 0.0),
      (LogicalKeyboardKey.arrowRight, 1.0, 0.0),
      (LogicalKeyboardKey.arrowUp, 0.0, -1.0),
      (LogicalKeyboardKey.arrowDown, 0.0, 1.0),
    ]) {
      // One gesture per key-repeat burst would be ideal; one entry per
      // press is fine for the toy — merge under a single key so holding
      // an arrow stays one undo entry.
      arrows[SingleActivator(key)] = () =>
          editor.nudgeSelection(dx, dy, mergeKey: 'nudge');
      arrows[SingleActivator(key, shift: true)] = () =>
          editor.nudgeSelection(dx * 10, dy * 10, mergeKey: 'nudge');
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): editor.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            editor.redo,
        const SingleActivator(LogicalKeyboardKey.backspace):
            editor.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.delete):
            editor.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.escape): editor.clearSelection,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            editor.duplicateSelection,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () => editor
            .setSelection([for (var n in editor.doc.root.children) n.name]),
        ...arrows,
      },
      // Any press inside the scope hands the keyboard back, whoever had
      // it: the scope holds no text fields, so there is nothing here that
      // wants the keys for itself.
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _node.requestFocus(),
        child: Focus(focusNode: _node, autofocus: true, child: widget.child),
      ),
    );
  }
}

/// Whether the platform's multi-select modifier is down at this instant —
/// how a tap knows to toggle instead of replace.
bool get _toggleModifier {
  var keys = HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight) ||
      keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight) ||
      keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
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
                      toggle: _toggleModifier,
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

/// Distinguishes one drag gesture from the next, so a whole drag merges
/// into ONE undo entry and the next drag starts a fresh one.
var _dragSeq = 0;

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
      editor.nudgeSelection(delta.dx, delta.dy, mergeKey: 'drag$_dragSeq');
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
      editor.perform('Reorder ${node.name}', mergeKey: 'drag$_dragSeq', () {
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
        onTapDown: (_) => editor.select(node, toggle: _toggleModifier),
        onPanDown: (d) => _downLocal = d.localPosition,
        onPanStart: (d) {
          _dragSeq++;
          if (!editor.isSelected(node)) editor.select(node);
          _apply(d.localPosition, d.localPosition - _downLocal);
        },
        onPanUpdate: (d) => _apply(d.localPosition, d.delta),
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
    widget.editor.perform(
      'Resize ${node.name}',
      mergeKey: 'resize$_dragSeq',
      () {
        var rect = node.measured;
        node.width = ((node.width ?? rect?.width ?? 100) + delta.dx).clamp(
          8,
          4000,
        );
        node.height = ((node.height ?? rect?.height ?? 100) + delta.dy).clamp(
          8,
          4000,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _downLocal = d.localPosition,
      onPanStart: (d) {
        _dragSeq++;
        _apply(d.localPosition - _downLocal);
      },
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

// ---------------------------------------------------------------------------
// Inspector
// ---------------------------------------------------------------------------

const _palette = <SceneColor?>[
  null,
  SceneColor(0xFFFFFFFF),
  SceneColor(0xFF1A1A1A),
  SceneColor(0xFF2B1B12),
  SceneColor(0xFF4A2F1F),
  SceneColor(0xFF6B4226),
  SceneColor(0xFFD8C9BD),
  SceneColor(0xFFE8632B),
  SceneColor(0xFFF2B705),
  SceneColor(0xFF3E7C4F),
  SceneColor(0xFF4A64D0),
];

class InspectorPanel extends StatelessWidget {
  const InspectorPanel(this.editor, {super.key});

  final SceneEditor editor;

  SceneDocument get doc => editor.doc;

  /// Every inspector edit is a door; consecutive edits of one property on
  /// one node merge into a single undo entry (live keystrokes, swatch
  /// browsing).
  void _door(String prop, void Function() fn) {
    var name = (editor.primary ?? doc.root).name;
    editor.perform('Edit $prop', mergeKey: 'inspect:$prop:$name', fn);
  }

  @override
  Widget build(BuildContext context) {
    var node = editor.primary ?? doc.root;
    var parent = node == doc.root ? null : doc.parentOf(node);
    var inFlex = parent != null && parent.layout != NodeLayout.absolute;

    return ListView(
      // Fresh field state per node: a reused NumField would commit the
      // previous node's text onto the next one on focus loss.
      key: ValueKey('inspector:${node.name}'),
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
                onChanged: (v) => _door('x', () => node.x = v ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                'Y',
                node.y,
                enabled: !inFlex && node != doc.root,
                onChanged: (v) => _door('y', () => node.y = v ?? 0),
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
                onChanged: (v) => _door('width', () => node.width = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                'H',
                node.height,
                nullable: true,
                hint: 'hug',
                onChanged: (v) => _door('height', () => node.height = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _label('Fill'),
        _swatches(node.fill, (c) => _door('fill', () => node.fill = c)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: NumField(
                'Corner',
                node.cornerRadius,
                onChanged: (v) =>
                    _door('corner', () => node.cornerRadius = v ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                'Opacity',
                node.opacity,
                onChanged: (v) =>
                    _door('opacity', () => node.opacity = (v ?? 1).clamp(0, 1)),
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
        onChanged: (v) => _door('text', () => t.text = v),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: NumField(
              'Size',
              t.fontSize,
              onChanged: (v) => _door('fontSize', () => t.fontSize = v ?? 14),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<SceneFontWeight>(
              initialValue: t.weight,
              decoration: const InputDecoration(
                labelText: 'Weight',
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: const [
                DropdownMenuItem(
                  value: SceneFontWeight.w400,
                  child: Text('Regular'),
                ),
                DropdownMenuItem(
                  value: SceneFontWeight.w500,
                  child: Text('Medium'),
                ),
                DropdownMenuItem(
                  value: SceneFontWeight.w600,
                  child: Text('Semibold'),
                ),
                DropdownMenuItem(
                  value: SceneFontWeight.w700,
                  child: Text('Bold'),
                ),
                DropdownMenuItem(
                  value: SceneFontWeight.w900,
                  child: Text('Black'),
                ),
              ],
              onChanged: (v) =>
                  _door('weight', () => t.weight = v ?? SceneFontWeight.w400),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _label('Color'),
      _swatches(
        t.color,
        (c) =>
            _door('color', () => t.color = c ?? const SceneColor(0xFF000000)),
      ),
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
        onSelectionChanged: (s) => _door('layout', () {
          var next = s.first;
          var origin = f.measured;
          if (next == NodeLayout.absolute) {
            for (var c in f.children) {
              var rect = c.measured;
              if (rect != null) {
                c.x = rect.left - (origin?.left ?? 0);
                c.y = rect.top - (origin?.top ?? 0);
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
              onChanged: (v) => _door('gap', () => f.gap = v ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NumField(
              'Padding',
              f.padding,
              onChanged: (v) => _door('padding', () => f.padding = v ?? 0),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (f.layout != NodeLayout.absolute)
        DropdownButtonFormField<SceneCrossAxisAlignment>(
          initialValue: f.crossAlign,
          decoration: const InputDecoration(
            labelText: 'Cross align',
            isDense: true,
          ),
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          items: const [
            DropdownMenuItem(
              value: SceneCrossAxisAlignment.start,
              child: Text('Start'),
            ),
            DropdownMenuItem(
              value: SceneCrossAxisAlignment.center,
              child: Text('Center'),
            ),
            DropdownMenuItem(
              value: SceneCrossAxisAlignment.end,
              child: Text('End'),
            ),
            DropdownMenuItem(
              value: SceneCrossAxisAlignment.stretch,
              child: Text('Stretch'),
            ),
          ],
          onChanged: (v) => _door(
            'crossAlign',
            () => f.crossAlign = v ?? SceneCrossAxisAlignment.center,
          ),
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
            onChanged: (v) => _door('args', () => e.args[arg.key] = v),
          )
        else
          TextFormField(
            key: ValueKey('${e.name}:${arg.key}'),
            initialValue: '${arg.value}',
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(labelText: arg.key, isDense: true),
            onChanged: (v) => _door('args', () => e.args[arg.key] = v),
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
        onChanged: (v) => _door('circle', () => s.circle = v),
      ),
    ];
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  );

  Widget _swatches(SceneColor? current, void Function(SceneColor?) onPick) {
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
                color: color?.flutter,
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

  // Commits only a CHANGE: a focus-loss echo of the value already held
  // must not open a door (it would spam the undo journal).
  void _commit() {
    var text = controller.text.trim();
    if (text.isEmpty) {
      var v = widget.nullable ? null : 0.0;
      if (widget.value != v) widget.onChanged(v);
      return;
    }
    var parsed = double.tryParse(text);
    if (parsed != null && parsed != widget.value) widget.onChanged(parsed);
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
        if (parsed != null && parsed != widget.value) widget.onChanged(parsed);
      },
      onSubmitted: (_) => _commit(),
    );
  }
}
