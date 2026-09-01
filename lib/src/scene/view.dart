// The scene, rendered by the app that owns it.
//
// This widget is the scene system's other deliverable. The editor's canvas is
// this widget in the app's own process — which is the whole reason the editor
// has no renderer of its own — and a scene that ships is this widget mounted
// in a screen. One renderer, so what you designed is what runs.
//
// External nodes are the seam: a scene names an entry, and the app hands over
// the real widget for it. Nothing about that widget crosses a wire — its
// mockup data, its theme, its own animations all live here, on this side.
import 'package:flutter/material.dart';

import '../previews/playhead.dart';
import 'core/model.dart';
import 'core/motion_runtime.dart';
import 'core/values.dart';
import 'flutter_bridge.dart';

/// Builds the app's widget for an external node — the registration the scene
/// v1 design settled on, handed in by the app rather than discovered.
typedef SceneExternalBuilder = Widget Function(
  BuildContext context,
  Map<String, Object?> args,
);

/// Reports what the layout measured, in artboard coordinates. The editor's
/// geometry comes from here: a flex child has no authored position, so the
/// only true answer is the one the renderer laid out.
typedef SceneMeasured = void Function(Map<String, SceneRect> rects);

class SceneView extends StatefulWidget {
  const SceneView(
    this.scene, {
    super.key,
    this.motion,
    this.externals = const {},
    this.selected = const {},
    this.onMeasured,
  });

  /// The live document. Edits and fx writes both notify it, and this widget
  /// redraws from the RENDERED plane — base composed with every fx writer —
  /// so a playing motion and a saved layout are one picture.
  final SceneDocument scene;

  /// What animates this scene, bound to it. Mounting one REGISTERS A
  /// PLAYHEAD: an export walks it, a test parks it, and `previews` can
  /// photograph the scene at any moment without the app wiring anything.
  ///
  /// The view never plays it — a clock is the app's business, and a
  /// [MotionPlayer] over the same playable is how a scene plays on screen.
  final Playable? motion;

  /// The app's widgets, by the entry name a node holds.
  final Map<String, SceneExternalBuilder> externals;

  /// Names to outline — editor chrome, and empty in a shipped scene.
  final Set<String> selected;

  final SceneMeasured? onMeasured;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> {
  final _keys = <String, GlobalKey>{};
  final _artboard = GlobalKey();

  GlobalKey _key(String name) => _keys.putIfAbsent(name, GlobalKey.new);

  String? _playheadId;

  @override
  void initState() {
    super.initState();
    installSceneFrameFlush();
    widget.scene.addListener(_onChanged);
    _mountPlayhead();
  }

  void _mountPlayhead() {
    var motion = widget.motion;
    if (motion == null) return;
    _playheadId = PlayheadRegistry.instance.attach(_ScenePlayhead(motion));
  }

  void _unmountPlayhead() {
    var id = _playheadId;
    if (id != null) PlayheadRegistry.instance.detach(id);
    _playheadId = null;
  }

  @override
  void didUpdateWidget(SceneView old) {
    super.didUpdateWidget(old);
    if (old.scene != widget.scene) {
      old.scene.removeListener(_onChanged);
      widget.scene.addListener(_onChanged);
    }
    if (old.motion != widget.motion) {
      _unmountPlayhead();
      _mountPlayhead();
    }
  }

  @override
  void dispose() {
    _unmountPlayhead();
    widget.scene.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Sweeps the laid-out boxes after the frame that drew them. Every node
  /// gets its rect relative to the artboard, which is the space the editor
  /// works in.
  void _sweep() {
    if (widget.onMeasured == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var root = _artboard.currentContext?.findRenderObject() as RenderBox?;
      if (root == null) return;
      var rects = <String, SceneRect>{};
      for (var (node, _) in widget.scene.walk()) {
        var box =
            _keys[node.name]?.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        var topLeft = box.localToGlobal(Offset.zero, ancestor: root);
        rects[node.name] = (topLeft & box.size).scene;
      }
      widget.onMeasured!(rects);
    });
  }

  @override
  Widget build(BuildContext context) {
    _sweep();
    var root = widget.scene.root;
    return SizedBox(
      key: _artboard,
      width: root.width ?? 1024,
      height: root.height ?? 500,
      // Material, not a bare ColoredBox: without a Material ancestor every
      // Text falls back to the debug style — the yellow double underline.
      child: Material(
        color: root.fill?.flutter ?? const Color(0x00000000),
        child: _node(context, root, root: true),
      ),
    );
  }

  Widget _node(BuildContext context, SceneNode n, {bool root = false}) {
    Widget? inner;
    switch (n) {
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
        var build = widget.externals[e.entry];
        inner = build == null
            // Named rather than blank: a scene naming an entry the app does
            // not register is a wiring mistake, and a silent gap reads as a
            // layout one.
            ? _MissingExternal(e.entry)
            : build(context, e.renderedArgs);
      case FrameNode f:
        var children = [for (var c in f.children) _child(context, f, c)];
        var gap = f.fxRendered('gap') as double;
        inner = switch (f.layout) {
          NodeLayout.absolute => Stack(
            clipBehavior: Clip.none,
            children: children,
          ),
          NodeLayout.row => Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: f.mainAlign.flutter,
            crossAxisAlignment: f.crossAlign.flutter,
            spacing: gap,
            children: children,
          ),
          NodeLayout.column => Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: f.mainAlign.flutter,
            crossAxisAlignment: f.crossAlign.flutter,
            spacing: gap,
            children: children,
          ),
        };
    }

    var circle = n is ShapeNode && n.circle;
    var fill = n.hasFx('fill') ? n.fxRendered('fill') as SceneColor : n.fill;
    var padding = n is FrameNode ? n.padding : 0.0;
    Widget result = Container(
      key: _key(n.name),
      width: n.width,
      height: n.height,
      padding: padding > 0
          ? EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.6)
          : null,
      foregroundDecoration: !root && widget.selected.contains(n.name)
          ? BoxDecoration(
              border: Border.all(color: const Color(0xFF4A64D0), width: 1.5),
            )
          : null,
      // The root's own fill is painted by the Material above, so a nested
      // decoration would double it.
      decoration: !root && (fill != null || n.cornerRadius > 0)
          ? BoxDecoration(
              color: fill?.flutter,
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle || n.cornerRadius == 0
                  ? null
                  : BorderRadius.circular(n.cornerRadius),
            )
          : null,
      child: inner,
    );

    var opacity = (n.fxRendered('opacity') as double).clamp(0.0, 1.0);
    if (opacity < 1) result = Opacity(opacity: opacity, child: result);

    // The imposed transforms have no authored slots — identity is the base —
    // so they wrap only while a writer moves them, about the node's centre.
    var tx = n.fxRendered('translateX') as double;
    var ty = n.fxRendered('translateY') as double;
    var scale = n.fxRendered('scale') as double;
    var rotate = n.fxRendered('rotate') as double;
    if (tx != 0 || ty != 0 || scale != 1 || rotate != 0) {
      var m = Matrix4.translationValues(tx, ty, 0);
      if (rotate != 0) m.rotateZ(rotate * 3.1415926535897932 / 180);
      if (scale != 1) m.multiply(Matrix4.diagonal3Values(scale, scale, 1));
      result = Transform(
        alignment: Alignment.center,
        transform: m,
        child: result,
      );
    }
    return result;
  }

  Widget _child(BuildContext context, FrameNode parent, SceneNode child) {
    var view = _node(context, child);
    if (parent.layout == NodeLayout.absolute) {
      return Positioned(left: child.x, top: child.y, child: view);
    }
    return view;
  }
}

class _MissingExternal extends StatelessWidget {
  const _MissingExternal(this.entry);

  final String entry;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFCC3333)),
    ),
    child: Text(
      'no widget registered for "$entry"',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 10, color: Color(0xFFCC3333)),
    ),
  );
}

/// A bound motion as a [Playhead]: parking it applies the fx plane for that
/// moment, and the document's own flush repaints whatever is watching. No
/// clock — that is the point, and what makes a walk repeatable.
class _ScenePlayhead implements Playhead {
  _ScenePlayhead(this.playable);

  final Playable playable;

  @override
  Duration get duration => playable.duration;

  @override
  void seek(Duration position) => playable.apply(position);
}
