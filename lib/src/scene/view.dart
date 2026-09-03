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

  /// Which axes of [n] its parent has already sized for it.
  ({bool width, bool height}) _stretchedBy(SceneNode n) {
    var parent = widget.scene.parentOf(n);
    if (parent is! FrameNode || parent.layout == NodeLayout.absolute) {
      return (width: false, height: false);
    }
    var row = parent.layout == NodeLayout.row;
    var mainFilled = row ? n.widthFills : n.heightFills;
    var crossStretched = parent.crossAlign == SceneCrossAxisAlignment.stretch;
    return (
      width: row ? mainFilled : crossStretched,
      height: row ? crossStretched : mainFilled,
    );
  }

  @override
  Widget build(BuildContext context) {
    _sweep();
    var root = widget.scene.root;
    // The three shapes a scene root comes in, and the only difference
    // between the three things a scene is for. A banner is fixed on both
    // axes; a screen takes the constraints the app hands it; a document is
    // fixed across and grows down. Fill is that: leave the axis alone and
    // let what is above decide.
    return SizedBox(
      key: _artboard,
      width: root.width,
      height: root.height,
      // Material, not a bare ColoredBox: without a Material ancestor every
      // Text falls back to the debug style — the yellow double underline.
      child: Material(
        color: root.fill?.flutter ?? const Color(0x00000000),
        // The root's corner lives here with its fill, since its decoration
        // is skipped below — a nested scene's root is often a pill.
        borderRadius: root.cornerRadius == 0
            ? null
            : BorderRadius.circular(root.cornerRadius),
        clipBehavior: root.cornerRadius == 0 ? Clip.none : Clip.antiAlias,
        child: _node(context, root, root: true),
      ),
    );
  }

  /// [prefix] namespaces the keys of a nested instance's nodes under the
  /// ref that holds them: two scenes both have a `root`.
  Widget _node(
    BuildContext context,
    SceneNode n, {
    bool root = false,
    String prefix = '',
  }) {
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
      case SceneRefNode r:
        var inst = r.instance;
        if (inst == null) {
          inner = _MissingScene(r.sceneClassName);
        } else {
          r.syncInstance();
          inner = _node(context, inst.root, prefix: '$prefix${r.name}/');
        }
      case FrameNode f:
        var gap = f.fxRendered('gap') as double;
        if (f.layout == NodeLayout.absolute) {
          inner = Stack(
            clipBehavior: Clip.none,
            children: [for (var c in f.children) _child(context, f, c, prefix)],
          );
          break;
        }
        var row = f.layout == NodeLayout.row;
        Widget flex({required bool expand}) {
          var children = [
            for (var c in f.children)
              _child(context, f, c, prefix, expand: expand),
          ];
          return row
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: f.mainAlign.flutter,
                  crossAxisAlignment: f.crossAlign.flutter,
                  spacing: gap,
                  children: children,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: f.mainAlign.flutter,
                  crossAxisAlignment: f.crossAlign.flutter,
                  spacing: gap,
                  children: children,
                );
        }

        // A child can only take what is left when there is a left: a flex
        // whose own main axis is unbounded has none, and Flutter throws
        // rather than guessing. Fill degrades to hug there, which is the
        // honest answer and what the editor has to say out loud.
        var anyFills = f.children.any(
          (c) => row ? c.widthFills : c.heightFills,
        );
        inner = anyFills
            ? LayoutBuilder(
                builder: (context, constraints) => flex(
                  expand: row
                      ? constraints.hasBoundedWidth
                      : constraints.hasBoundedHeight,
                ),
              )
            : flex(expand: false);
    }

    var circle = n is ShapeNode && n.circle;
    var fill = n.hasFx('fill') ? n.fxRendered('fill') as SceneColor : n.fill;
    var padding = n is FrameNode ? n.padding : 0.0;
    // A node the parent already stretched must not also ask for infinity:
    // `Expanded` hands it a tight box, and an infinite width inside one is
    // an unbounded-constraint error rather than a wide node.
    var stretched = _stretchedBy(n);
    Widget result = Container(
      key: _key('$prefix${n.name}'),
      width: stretched.width ? null : n.width,
      height: stretched.height ? null : n.height,
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

  Widget _child(
    BuildContext context,
    FrameNode parent,
    SceneNode child,
    String prefix, {
    bool expand = false,
  }) {
    var view = _node(context, child, prefix: prefix);
    if (parent.layout == NodeLayout.absolute) {
      return Positioned(left: child.x, top: child.y, child: view);
    }
    // Fill along the parent's main axis is the parent handing out what is
    // left, which is `Expanded` and nothing else. Along the cross axis it is
    // the child asking for all of it, which its own box already does with an
    // infinite width or height.
    var fillsMain = parent.layout == NodeLayout.row
        ? child.widthFills
        : child.heightFills;
    return fillsMain && expand ? Expanded(child: view) : view;
  }
}

class _MissingScene extends StatelessWidget {
  const _MissingScene(this.sceneClassName);

  final String sceneClassName;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFCC3333)),
    ),
    child: Text(
      'no scene "$sceneClassName" here',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 10, color: Color(0xFFCC3333)),
    ),
  );
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
