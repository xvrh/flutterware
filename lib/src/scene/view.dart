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
import 'core/motion_model.dart';
import 'core/props.dart';
import 'core/motion_runtime.dart';
import 'core/values.dart';
import 'flutter_bridge.dart';

/// Reports what the layout measured, in artboard coordinates. The editor's
/// geometry comes from here: a flex child has no authored position, so the
/// only true answer is the one the renderer laid out.
///
/// Keyed by the NODE, not by its name. A compiled scene has no names — the
/// field names live in the source, where the editor reads them — so a
/// name-keyed report would collide every node of it onto one empty string.
/// Whoever holds names (the editor, the guest naming rects for the wire)
/// puts them on at its own edge.
typedef SceneMeasured = void Function(Map<SceneNode, SceneRect> rects);

/// The same rects under the names the nodes carry — what the guest sends
/// back over the wire, and what a surface holding a PARSED document asks
/// its geometry by.
///
/// Meaningless for a compiled scene, whose nodes have no names: every entry
/// would land on the empty string. That is the whole reason [SceneMeasured]
/// hands over the nodes and this is a separate step.
Map<String, SceneRect> namedRects(Map<SceneNode, SceneRect> rects) => {
  for (var entry in rects.entries)
    if (entry.key.name.isNotEmpty) entry.key.name: entry.value,
};

class SceneView extends StatefulWidget {
  /// Draws a scene an app COMPILED — `SceneView(BannerScene())`, which is
  /// the whole of what mounting one takes.
  ///
  /// The definition holds its document (built once, `late final`), so this
  /// costs nothing per rebuild. It does not make the definition safe to
  /// build in `build()`: a fresh `BannerScene()` is fresh nodes, and a
  /// player would go on writing its fx onto the ones that went away. Hold
  /// it in a field.
  SceneView(
    SceneDefinition definition, {
    super.key,
    SceneMotion? motion,
    this.selected = const {},
    this.onMeasured,
  }) : scene = definition.scene,
       motion = motion?.playable;

  /// Draws a document that was READ — parsed from source, or decoded off
  /// the editor's wire. There is no definition behind one of those, which is
  /// why it is a door of its own rather than the same one.
  const SceneView.document(
    this.scene, {
    super.key,
    this.motion,
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

  /// Names to outline — editor chrome, and empty in a shipped scene.
  final Set<String> selected;

  final SceneMeasured? onMeasured;

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> {
  /// Keyed by the NODE, not by its name. A compiled scene has no names —
  /// identity there is the object — and two nodes sharing one key is a
  /// duplicate-GlobalKey crash rather than a wrong picture.
  final _keys = <SceneNode, GlobalKey>{};
  final _artboard = GlobalKey();

  GlobalKey _key(SceneNode node) => _keys.putIfAbsent(node, GlobalKey.new);

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
      var rects = <SceneNode, SceneRect>{};
      SceneRect? visit(SceneNode node) {
        var box = _keys[node]?.currentContext?.findRenderObject() as RenderBox?;
        SceneRect? rect;
        if (box != null && box.hasSize) {
          rect =
              (box.localToGlobal(Offset.zero, ancestor: root) & box.size).scene;
        }
        SceneRect? spanned;
        for (var child in node.children) {
          var childRect = visit(child);
          if (childRect == null) continue;
          spanned = spanned == null ? childRect : _union(spanned, childRect);
        }
        // A table row draws no box of its own — the table lays out the
        // cells and paints the row behind them — so the row IS what its
        // cells span, which is the rect the editor selects and drops on.
        rect ??= spanned;
        if (rect != null) rects[node] = rect;
        return rect;
      }

      visit(widget.scene.root);
      widget.onMeasured!(rects);
    });
  }

  /// How far the children of a free frame reach along one axis: the
  /// authored size where there is one, and what the last layout measured
  /// where there is not.
  double _freeExtent(FrameNode f, {required bool horizontal}) {
    var extent = 0.0;
    for (var child in f.children) {
      var authored = horizontal ? child.width : child.height;
      var size = authored != null && authored.isFinite
          ? authored
          : switch (child.measured) {
              var m? => horizontal ? m.width : m.height,
              _ => 0.0,
            };
      var end = (horizontal ? child.x : child.y) + size;
      if (end > extent) extent = end;
    }
    return extent;
  }

  /// Which axes of [n] its parent has already sized for it. The parent is
  /// passed rather than looked up: a repeated copy hangs in no tree.
  ({bool width, bool height}) _stretchedBy(SceneNode n, FrameNode? parent) {
    if (parent == null || parent.layout == NodeLayout.absolute) {
      return (width: false, height: false);
    }
    // A cell's width is the column's, and a cell that also asked for one
    // would be fighting the table for it.
    if (parent.layout == NodeLayout.table) {
      return (width: true, height: false);
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
        borderRadius: root.corners.isZero ? null : root.corners.flutter,
        clipBehavior: root.corners.isZero && !root.clip
            ? Clip.none
            : Clip.antiAlias,
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
    FrameNode? parent,
  }) {
    Widget? inner;
    switch (n) {
      case TextNode t:
        inner = Text(
          t.text,
          textAlign: t.align.flutter,
          maxLines: t.maxLines,
          overflow: t.maxLines == null
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
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
        // A compiled node reaches the app's declaration through its own
        // generated class, so nothing is passed in for it. A node that
        // arrived as data was bound by whoever holds the declarations.
        var built = e.buildWidget();
        inner = built == null
            // Named rather than blank: a scene naming an entry nothing can
            // build is a wiring mistake, and a silent gap reads as a layout
            // one.
            ? _MissingExternal(e.entry)
            : _asWidget(built, e.entry);
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
          var stack = Stack(
            clipBehavior: Clip.none,
            children: [
              for (var c in f.children)
                if (c.visible)
                  for (var drawn in widget.scene.expand(c))
                    _child(context, f, drawn, prefix),
            ],
          );
          // A stack cannot lay out under an unbounded constraint, and a
          // column hands its children exactly that on the main axis. A free
          // frame with no size of its own inside one would assert, so it is
          // given the extent its children actually reach — which is the only
          // size a free frame has ever meant.
          inner = LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              width: constraints.hasBoundedWidth
                  ? null
                  : _freeExtent(f, horizontal: true),
              height: constraints.hasBoundedHeight
                  ? null
                  : _freeExtent(f, horizontal: false),
              child: stack,
            ),
          );
          break;
        }
        if (f.layout == NodeLayout.table) {
          inner = _table(context, f, prefix);
          break;
        }
        var row = f.layout == NodeLayout.row;
        Widget flex({required bool expand}) {
          var children = [
            for (var c in f.children)
              if (c.visible)
                for (var drawn in widget.scene.expand(c))
                  _child(context, f, drawn, prefix, expand: expand),
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
    var padding = n is FrameNode ? n.padding : SceneEdges.zero;
    // A node the parent already stretched must not also ask for infinity:
    // `Expanded` hands it a tight box, and an infinite width inside one is
    // an unbounded-constraint error rather than a wide node.
    var stretched = _stretchedBy(n, parent);
    Widget result = Container(
      key: _key(n),
      width: stretched.width ? null : n.width,
      height: stretched.height ? null : n.height,
      padding: padding.isZero ? null : padding.flutter,
      foregroundDecoration: !root && widget.selected.contains(n.name)
          ? BoxDecoration(
              border: Border.all(color: const Color(0xFF4A64D0), width: 1.5),
            )
          : null,
      // The root's own fill is painted by the Material above, so a nested
      // decoration would double it.
      decoration:
          !root && (fill != null || n.borderColor != null || !n.corners.isZero)
          ? BoxDecoration(
              color: fill?.flutter,
              border: n.borderColor == null
                  ? null
                  : Border.all(
                      color: n.borderColor!.flutter,
                      width: n.borderWidth,
                    ),
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: circle || n.corners.isZero
                  ? null
                  : n.corners.flutter,
            )
          : null,
      child: inner,
    );
    // A clipping frame cuts its children at its own corners; a bounded node
    // is held between its bounds whatever its parent hands it.
    if (n is FrameNode && n.clip && !root) {
      result = ClipRRect(borderRadius: n.corners.flutter, child: result);
    }
    if (n.minWidth != null ||
        n.maxWidth != null ||
        n.minHeight != null ||
        n.maxHeight != null) {
      result = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: n.minWidth ?? 0,
          maxWidth: n.maxWidth ?? double.infinity,
          minHeight: n.minHeight ?? 0,
          maxHeight: n.maxHeight ?? double.infinity,
        ),
        child: result,
      );
    }

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

  /// A table: rows that agree on their columns.
  ///
  /// The tracks belong to the frame, so every row is measured against the
  /// same ones — which is the only way a column hugging its widest cell can
  /// mean anything, and the reason stacked rows are not a table.
  Widget _table(BuildContext context, FrameNode f, String prefix) {
    var rows = [
      for (var c in f.children)
        if (c.visible)
          for (var drawn in widget.scene.expand(c)) drawn,
    ];
    List<SceneNode> cellsOf(SceneNode row) =>
        row is FrameNode ? row.children : [row];
    var count = f.columns.length;
    for (var r in rows) {
      var cells = cellsOf(r).length;
      if (cells > count) count = cells;
    }
    if (rows.isEmpty || count == 0) return const SizedBox.shrink();

    Widget table({required bool bounded}) => Table(
      columnWidths: {
        for (var i = 0; i < count; i++)
          i: _track(
            i < f.columns.length ? f.columns[i] : null,
            bounded: bounded,
          ),
      },
      defaultVerticalAlignment: switch (f.crossAlign) {
        SceneCrossAxisAlignment.start => TableCellVerticalAlignment.top,
        SceneCrossAxisAlignment.end => TableCellVerticalAlignment.bottom,
        SceneCrossAxisAlignment.stretch => TableCellVerticalAlignment.fill,
        _ => TableCellVerticalAlignment.middle,
      },
      children: [
        for (var r in rows)
          TableRow(
            decoration: _rowDecoration(r),
            children: [
              for (var i = 0; i < count; i++)
                if (cellsOf(r) case var cells)
                  i < cells.length
                      ? Padding(
                          padding: f.cellPadding.flutter,
                          child: _node(
                            context,
                            cells[i],
                            prefix: prefix,
                            parent: f,
                          ),
                        )
                      : const SizedBox.shrink(),
            ],
          ),
      ],
    );

    // A column that takes what is left needs there to BE a left, exactly as
    // `Expanded` does: under an unbounded width it hugs instead.
    var anyFills = f.columns.any((c) => c != null && c.isInfinite);
    return anyFills
        ? LayoutBuilder(
            builder: (context, constraints) =>
                table(bounded: constraints.hasBoundedWidth),
          )
        : table(bounded: false);
  }

  TableColumnWidth _track(double? width, {required bool bounded}) =>
      switch (width) {
        null => const IntrinsicColumnWidth(),
        var w when w.isInfinite =>
          bounded ? const FlexColumnWidth() : const IntrinsicColumnWidth(),
        var w => FixedColumnWidth(w),
      };

  /// What paints behind a table row. A row under a table contributes its
  /// decoration and nothing else — the table lays the cells out, so the
  /// row's own box, padding and size have nowhere to apply.
  Decoration? _rowDecoration(SceneNode r) {
    var selected = widget.selected.contains(r.name);
    var fill = r.hasFx('fill') ? r.fxRendered('fill') as SceneColor : r.fill;
    if (fill == null && r.borderColor == null && !selected) return null;
    // A row has no box to wrap in an Opacity, so it fades what it paints.
    var opacity = (r.fxRendered('opacity') as double).clamp(0.0, 1.0);
    return BoxDecoration(
      color: fill?.flutter.withValues(alpha: fill.alpha / 255 * opacity),
      border: selected
          ? Border.all(color: const Color(0xFF4A64D0), width: 1.5)
          : r.borderColor == null
          ? null
          : Border.all(
              color: r.borderColor!.flutter.withValues(
                alpha: r.borderColor!.alpha / 255 * opacity,
              ),
              width: r.borderWidth,
            ),
      borderRadius: r.corners.isZero ? null : r.corners.flutter,
    );
  }

  Widget _child(
    BuildContext context,
    FrameNode parent,
    SceneNode child,
    String prefix, {
    bool expand = false,
  }) {
    var view = _node(context, child, prefix: prefix, parent: parent);
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

/// Gives every external node in [doc] the builder its label names.
///
/// A scene the app COMPILED needs none of this: each node holds its own
/// generated arguments, which reach the declaration themselves. This is for
/// a document that arrived as DATA — over the editor's wire, or read back
/// from a saved pair — where the generated type could not travel and the
/// label is all that did.
///
/// [tokens] are the app's declared tokens, for the opaque ones: an argument
/// that arrived as `{'token': 'cta'}` — the editor never held the object —
/// becomes the declared object here, before the builder sees it. A read
/// document is the only one that needs this; a compiled scene reads
/// `tokens.cta` itself.
void bindExternals(
  SceneDocument doc,
  List<ExternalWidget> declarations, {
  List<Token<Object?>> tokens = const [],
}) {
  var byEntry = {for (var w in declarations) w.entry: w};
  var byName = {for (var t in tokens) t.name: t.value};
  for (var (node, _) in doc.walk()) {
    resolveExports(node, byName);
    if (node is! ExternalNode) continue;
    var build = byEntry[node.entry]?.build;
    node.builder = build == null
        ? null
        : (args) => build(resolveTokenArgs(args, byName));
  }
}

/// Puts the app's own values on the properties of [node] bound to them.
///
/// An EXPORT — `Token<Color>('brand', AppColors.brand)` in the group's
/// declaration — reaches the editor as a name; the editor never holds the
/// value and sends the binding as it is. This end holds the object, so a
/// `fill` bound to `brand` takes the app's colour here, a `double` a number,
/// a `String` text. A `TextStyle` in the style slot is laid UNDER the
/// text's own values: every property the app's style sets and the text
/// left at its default takes the style's — the resolution the compiled
/// `TextNode(…, style: tokens.title)` does with `fontSize ?? style?.
/// fontSize ?? 16`, so the two planes agree.
void resolveExports(SceneNode node, Map<String, Object?> exports) {
  for (var e in node.bindings.entries) {
    var prop = e.key;
    switch (e.value) {
      case TokenRef(:var name) when !prop.startsWith('args.'):
        if (!exports.containsKey(name)) continue;
        var value = switch (exports[name]) {
          Color c => c.scene,
          SceneColor c => c,
          num n => n.toDouble(),
          String s => s,
          bool b => b,
          _ => null,
        };
        if (value != null) setSceneProperty(node, prop, value);
      case StyleRef(:var name) when node is TextNode:
        var style = switch (exports[name]) {
          TextStyle s => sceneTextStyleOf(s),
          SceneTextStyle s => s,
          _ => null,
        };
        if (style == null) continue;
        var props = {for (var p in scenePropsOf(node)) p.name: p};
        for (var f in style.values.entries) {
          var prop = props[f.key];
          if (prop == null) continue;
          if (isSceneDefault(prop, prop.read(node))) {
            setSceneProperty(node, f.key, f.value);
          }
        }
      default:
        break;
    }
  }
}

/// [args] with every opaque-token marker replaced by the token's object;
/// a marker naming nothing the app declared resolves to null, which is the
/// widget's own fallback.
SceneArgs resolveTokenArgs(SceneArgs args, Map<String, Object?> tokens) =>
    SceneArgs({
      for (var name in args.names)
        name: switch (tokenMarkerName(args.raw(name))) {
          var token? => tokens[token],
          null => args.raw(name),
        },
    });

/// A builder returns `Object`, because the half of the model that declares
/// it is pure Dart. This is where that becomes a widget again, and where a
/// builder that returned something else says so instead of crashing the
/// frame.
Widget _asWidget(Object built, String entry) => built is Widget
    ? built
    : _MissingExternal('$entry built a ${built.runtimeType}, not a widget');

SceneRect _union(SceneRect a, SceneRect b) {
  var left = a.left < b.left ? a.left : b.left;
  var top = a.top < b.top ? a.top : b.top;
  var right = a.right > b.right ? a.right : b.right;
  var bottom = a.bottom > b.bottom ? a.bottom : b.bottom;
  return SceneRect(left, top, right - left, bottom - top);
}
