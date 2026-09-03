// The scene document — a deliberately *uniform* node: every node carries the
// same styling bag (fill, corner, opacity) and the same geometry slots.
// Graduated from the canvas-toy spike 2026-09-01; pure Dart by decision
// (2026-09-01-scene-graduation-plan.md) so the headless surface can hold it.
import 'listenable.dart';
import 'values.dart';

enum NodeLayout { absolute, row, column }

/// A node's name is its identity everywhere — the wire, the rects, the hit
/// targets — and in the file it is the *field name* the node is declared
/// under, so it must be a valid Dart identifier.
final _identifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
const _reserved = {
  // Dart's reserved words — a field cannot be named these.
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default',
  'do', 'else', 'enum', 'extends', 'false', 'final', 'finally', 'for', 'if',
  'in', 'is', 'new', 'null', 'rethrow', 'return', 'super', 'switch', 'this',
  'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

bool isValidNodeName(String name) =>
    _identifier.hasMatch(name) && !_reserved.contains(name);

/// The typed hole: a constructor parameter whose default is the mockup.
/// Declared in the file as a primary-constructor formal with a default;
/// referenced by node properties by bare identifier. Parameters share the
/// class namespace with node fields.
enum SceneParamKind { string, number, color }

class SceneParamDecl {
  SceneParamDecl(this.name, this.kind, this.defaultValue);

  final String name;
  final SceneParamKind kind;

  /// String, double or [SceneColor] — the mockup, read by every consumer
  /// that passes no argument (the editor, the export matrix at the base
  /// point).
  final Object defaultValue;

  String get typeName => switch (kind) {
    SceneParamKind.string => 'String',
    SceneParamKind.number => 'double',
    SceneParamKind.color => 'Color',
  };
}

sealed class SceneNode {
  SceneNode(this.name);

  /// The node's identity — the field name in the file. Mutable only so the
  /// editor's rename door can move it; everything keyed by it (measured
  /// rects, keys, groups) is re-pointed by that door.
  String name;

  // Authored geometry. x/y are meaningful only under an absolute parent.
  double x = 0;
  double y = 0;

  /// Size along each axis, three-valued in one field:
  ///
  /// - `null` — **hug**: as big as the content needs.
  /// - a finite number — **fixed**.
  /// - [double.infinity] — **fill**: as much as the parent gives.
  ///
  /// The sentinel is Flutter's own vocabulary rather than an invention:
  /// `Container(width: double.infinity)` already means this, so the value
  /// reads the way it behaves and every reader that only passes it through
  /// keeps working. It is not JSON, though — `jsonEncode` refuses a
  /// non-finite double — so both the wire and the file spell it out; see
  /// [sizeToWire].
  ///
  /// Fill along the parent's MAIN axis needs that parent to be bounded on
  /// it: a column that hugs its height has no leftover to hand out. The
  /// renderer honours what it can and the editor is where the contradiction
  /// has to be shown, not hidden.
  double? width;
  double? height;

  /// Whether this node takes what the parent gives along each axis.
  bool get widthFills => width != null && width!.isInfinite;
  bool get heightFills => height != null && height!.isInfinite;

  // The uniform styling bag — the bet under test.
  SceneColor? fill;

  /// A line around the node, or none. Two fields rather than one value,
  /// because the file's vocabulary is flat named arguments and a
  /// `Border(...)` would be a construct the grammar does not have.
  SceneColor? borderColor;
  double borderWidth = 1;

  double cornerRadius = 0;
  double opacity = 1;

  /// Laid-out rect in artboard coordinates, swept after each frame by
  /// whichever renderer measured it.
  SceneRect? measured;

  /// Which properties read a parameter: property key → parameter name.
  /// The property still holds the resolved value (the default, until
  /// [SceneDocument.applyArgs]); the ref is provenance, and it survives a
  /// save only while the value still equals the parameter's default.
  final paramRefs = <String, String>{};

  /// The evaluated plane: per-frame contributions composed OVER the
  /// authored values above, keyed by (writer, property) in writer-stack
  /// order — the order is normative (× does not bit-commute). Motion lanes
  /// and app [Effect]s write here; Save never reads it; a cancelled writer
  /// clears its own entries and the authored value was never touched.
  final fx = <(Object, String), Object>{};

  SceneDocument? _doc;

  void writeFx(Object writer, String prop, Object value) {
    fx[(writer, prop)] = value;
    _doc?.fxTick();
  }

  void removeFx(Object writer, String prop) {
    if (fx.remove((writer, prop)) != null) _doc?.fxTick();
  }

  void clearFxWriter(Object writer) {
    var before = fx.length;
    fx.removeWhere((k, _) => identical(k.$1, writer));
    if (fx.length != before) _doc?.fxTick();
  }

  /// Whether any writer currently contributes to [prop] — the renderer asks
  /// this where the authored value's absence means something (a null fill
  /// draws no decoration; a composed fill draws one).
  bool hasFx(String prop) => fx.keys.any((k) => k.$2 == prop);

  /// The composed value the renderer should draw: authored base folded with
  /// every contribution through the derived operator table — opacity and
  /// scale multiply, translations and rotation add, everything else
  /// replaces in stack order.
  Object fxRendered(String prop) {
    var v = _fxBase(prop);
    for (var entry in fx.entries) {
      if (entry.key.$2 != prop) continue;
      v = switch (prop) {
        'opacity' || 'scale' => (v as double) * (entry.value as double),
        'translateX' ||
        'translateY' ||
        'rotate' => (v as double) + (entry.value as double),
        _ => entry.value,
      };
    }
    return v;
  }

  Object _fxBase(String prop) => switch (prop) {
    'opacity' => opacity,
    'translateX' || 'translateY' || 'rotate' => 0.0,
    'scale' => 1.0,
    'fontSize' => (this as TextNode).fontSize,
    'color' => (this as TextNode).color,
    'gap' => (this as FrameNode).gap,
    'fill' => fill ?? const SceneColor(0x00000000),
    _ => throw ArgumentError('no animatable property "$prop"'),
  };

  /// Mint an app-side fx writer. Handles are the only app surface — two
  /// independent effects on one property compose instead of colliding, and
  /// clearing one leaves the others (sketch 25).
  Effect effect() => Effect._(this);

  String get typeName;

  List<SceneNode> get children => const [];
}

/// One app-side fx writer: cosmetic, composed, never saved. Setting a
/// property to null removes that contribution; [clear] removes them all.
class Effect {
  Effect._(this._node);

  final SceneNode _node;

  // Each property reads back this writer's OWN contribution (null when it
  // has none) — the composed result is the node's [SceneNode.fxRendered].
  double? get opacity => _get('opacity');
  set opacity(double? v) => _set('opacity', v);
  double? get scale => _get('scale');
  set scale(double? v) => _set('scale', v);
  double? get translateX => _get('translateX');
  set translateX(double? v) => _set('translateX', v);
  double? get translateY => _get('translateY');
  set translateY(double? v) => _set('translateY', v);
  double? get rotate => _get('rotate');
  set rotate(double? v) => _set('rotate', v);

  double? _get(String prop) => _node.fx[(this, prop)] as double?;

  void _set(String prop, double? v) {
    if (v == null) {
      _node.removeFx(this, prop);
    } else {
      _node.writeFx(this, prop, v);
    }
  }

  void clear() => _node.clearFxWriter(this);
}

class FrameNode extends SceneNode {
  FrameNode(super.name, {this.layout = NodeLayout.absolute});

  NodeLayout layout;
  double gap = 8;
  SceneEdges padding = SceneEdges.zero;
  SceneMainAxisAlignment mainAlign = SceneMainAxisAlignment.start;
  SceneCrossAxisAlignment crossAlign = SceneCrossAxisAlignment.center;

  @override
  final List<SceneNode> children = [];

  @override
  String get typeName => 'Frame';
}

class TextNode extends SceneNode {
  TextNode(super.name, this.text);

  String text;
  double fontSize = 16;
  SceneFontWeight weight = SceneFontWeight.w400;
  SceneColor color = const SceneColor(0xFF1A1A1A);
  SceneTextAlign align = SceneTextAlign.left;

  /// How many lines before it is cut with an ellipsis, or null for as many
  /// as it takes. A banner filled per language is the reason: the layout
  /// that fits English has to survive German, and something has to give.
  int? maxLines;

  @override
  String get typeName => 'Text';
}

class ShapeNode extends SceneNode {
  ShapeNode(super.name, {this.circle = false});

  bool circle;

  @override
  String get typeName => 'Shape';
}

/// A widget the editor has never compiled against. The editor knows its
/// entry name and its wire-able args; the guest holds the real builder and
/// the mockups.
class ExternalNode extends SceneNode {
  ExternalNode(super.name, this.entry, {Map<String, Object?>? args})
    : args = args ?? {};

  final String entry;
  final Map<String, Object?> args;

  /// Authored args with fx contributions folded in (an ext arg's operator
  /// is replace, in stack order) — what the guest should render.
  Map<String, Object?> get renderedArgs {
    var out = Map.of(args);
    for (var entry in fx.entries) {
      var prop = entry.key.$2;
      if (prop.startsWith('args.')) out[prop.substring(5)] = entry.value;
    }
    return out;
  }

  @override
  String get typeName => 'Ext';
}

/// An instance of another scene, by class name, with that scene's
/// parameters overridden by [args].
///
/// The instance's internals are not addressable from here — the nesting
/// law: the parent sees one box, the child is edited in its own file. What
/// the parent may animate is the imposed vocabulary on the box plus the
/// child's declared parameters, as `args.<param>` tracks.
///
/// [instance] is runtime state, like `measured`: whoever can find files —
/// the workspace — resolves the class name and instantiates the child with
/// [args]; nothing serializes it, and a node nobody resolved draws as a
/// placeholder naming what it wanted.
class SceneRefNode extends SceneNode {
  SceneRefNode(super.name, this.sceneClassName, {Map<String, Object?>? args})
    : args = args ?? {};

  final String sceneClassName;
  final Map<String, Object?> args;

  SceneDocument? instance;

  /// The authored args with the motion's `args.*` writes on top.
  Map<String, Object?> get renderedArgs {
    var out = Map.of(args);
    for (var entry in fx.entries) {
      var prop = entry.key.$2;
      if (prop.startsWith('args.')) out[prop.substring(5)] = entry.value;
    }
    return out;
  }

  /// Puts the rendered args onto the instance — every declared parameter,
  /// so one the motion stopped writing falls back to its default rather
  /// than staying wherever the last frame left it.
  void syncInstance() {
    var inst = instance;
    if (inst == null) return;
    inst.applyArgs({
      for (var p in inst.params) p.name: p.defaultValue,
      ...renderedArgs,
    });
  }

  @override
  String get typeName => 'Scene';
}

/// A fresh copy of [template] with [args] applied to its parameters — what a
/// [SceneRefNode.instance] is. The copy keeps the template's parameter
/// declarations and `paramRefs`, so it can take new args later.
SceneDocument instantiateScene(
  SceneDocument template,
  Map<String, Object?> args,
) {
  var doc = SceneDocument(deepCopyNode(template.root) as FrameNode)
    ..params.addAll(template.params);
  doc.applyArgs(args);
  return doc;
}

class SceneDocument extends SceneListenable {
  SceneDocument(this.root) {
    _adopt();
  }

  final FrameNode root;

  /// Every node knows its document, so an fx write anywhere schedules the
  /// one coalesced flush. Re-swept after each [edit] — structure may move.
  void _adopt() {
    for (var (node, _) in walk()) {
      node._doc = this;
    }
  }

  var _fxScheduled = false;

  /// The probed frame-aligned flush (500 writes → 1 rebuild): coalesce all
  /// fx writes of a batch into one notification, through whatever
  /// [sceneFlushScheduler] the process installed.
  void fxTick() {
    if (_fxScheduled) return;
    _fxScheduled = true;
    sceneFlushScheduler(() {
      _fxScheduled = false;
      notifyListeners();
    });
  }

  /// The scene's declared parameters, in declaration order.
  final params = <SceneParamDecl>[];

  /// Instantiate: set every parameter-bound property whose parameter is
  /// named in [args]. This is what the export matrix does per language and
  /// what a caller's arguments do at mount — the model-level half of
  /// `BannerScene(title: …)`.
  void applyArgs(Map<String, Object?> args) {
    edit(() {
      for (var (node, _) in walk()) {
        for (var entry in node.paramRefs.entries) {
          if (!args.containsKey(entry.value)) continue;
          var v = args[entry.value];
          switch (entry.key) {
            case 'x':
              node.x = (v! as num).toDouble();
            case 'y':
              node.y = (v! as num).toDouble();
            case 'width':
              node.width = sizeFromWire(v);
            case 'height':
              node.height = sizeFromWire(v);
            case 'corner':
              node.cornerRadius = (v! as num).toDouble();
            case 'opacity':
              node.opacity = (v! as num).toDouble();
            case 'fill':
              node.fill = v as SceneColor?;
            case 'text':
              (node as TextNode).text = v! as String;
            case 'fontSize':
              (node as TextNode).fontSize = (v! as num).toDouble();
            case 'color':
              (node as TextNode).color = v! as SceneColor;
            case 'gap':
              (node as FrameNode).gap = (v! as num).toDouble();
            case 'padding':
              (node as FrameNode).padding = SceneEdges.all(
                (v! as num).toDouble(),
              );
          }
        }
      }
    });
  }

  /// Bumped when a post-frame sweep finds moved geometry, so overlays repaint
  /// without rebuilding the scene.
  final geometryEpoch = SceneValue(0);

  void edit(void Function() fn) {
    fn();
    _adopt();
    notifyListeners();
  }

  /// The wire the scene host renders from — data, never code, and a
  /// PICTURE rather than a document: it carries rendered values (base op
  /// fx), so a playing motion reaches the guest as a stream of these, one
  /// per flush. Selection is editor chrome riding along for hosts that
  /// outline it — the editor's, never the document's.
  ///
  /// Deliberately not `toJson`: that name belongs to the authored document
  /// (`SceneDocumentJson.toJson`), which is what a guest needs when it will
  /// evaluate the motion itself instead of being fed frames.
  Map<String, dynamic> toWire({Iterable<String> selected = const []}) => {
    'root': _json(root),
    'selected': [...selected],
  };

  Map<String, dynamic> _json(SceneNode n) {
    var tx = n.fxRendered('translateX') as double;
    var ty = n.fxRendered('translateY') as double;
    var scale = n.fxRendered('scale') as double;
    var rotate = n.fxRendered('rotate') as double;
    var fill = n.hasFx('fill') ? n.fxRendered('fill') as SceneColor : n.fill;
    return {
      'name': n.name,
      'x': n.x,
      'y': n.y,
      'w': sizeToWire(n.width),
      'h': sizeToWire(n.height),
      'fill': fill?.argb,
      if (n.borderColor case var b?) 'border': [b.argb, n.borderWidth],
      'corner': n.cornerRadius,
      'opacity': n.fxRendered('opacity'),
      // The imposed transforms have no authored slots — identity is the
      // base — so they ride the wire only when a writer moves them.
      // [translateX, translateY, scale, rotate°], applied about the center.
      if (tx != 0 || ty != 0 || scale != 1 || rotate != 0)
        'fx': [tx, ty, scale, rotate],
      ...switch (n) {
        FrameNode f => {
          'kind': 'frame',
          'layout': f.layout.name,
          'gap': f.fxRendered('gap'),
          'padding': f.padding.toWire(),
          'mainAlign': f.mainAlign.index,
          'crossAlign': f.crossAlign.index,
          'children': [for (var c in f.children) _json(c)],
        },
        TextNode t => {
          'kind': 'text',
          'align': t.align.index,
          if (t.maxLines != null) 'maxLines': ?t.maxLines,
          'text': t.text,
          'fontSize': t.fxRendered('fontSize'),
          'weight': t.weight.index,
          'color': (t.fxRendered('color') as SceneColor).argb,
        },
        ShapeNode s => {'kind': 'shape', 'circle': s.circle},
        ExternalNode e => {
          'kind': 'ext',
          'entry': e.entry,
          'args': e.renderedArgs,
        },
        SceneRefNode r => _refWire(r),
      },
    };
  }

  /// The instance's own picture, flattened under the ref node's box: the
  /// host draws frames and needs no resolver. Internal names are prefixed
  /// with the ref's, so a measured rect never lands on a parent node by
  /// coincidence — and never lands at all, since only parent names are
  /// looked up.
  Map<String, dynamic> _refWire(SceneRefNode r) {
    var inst = r.instance;
    if (inst == null) {
      return {'kind': 'frame', 'layout': 'absolute', 'children': const []};
    }
    r.syncInstance();
    var picture = inst._json(inst.root);
    Map<String, dynamic> prefixed(Map<String, dynamic> json) => {
      ...json,
      'name': '${r.name}/${json['name']}',
      if (json['children'] case List children)
        'children': [
          for (var c in children) prefixed(c as Map<String, dynamic>),
        ],
    };
    var children = (picture['children'] as List? ?? const [])
        .map((c) => prefixed(c as Map<String, dynamic>))
        .toList();
    // The box is the ref's; the child's root supplies what the ref leaves
    // to hug (size) or inherit (fill, corner). Opacities multiply.
    return {
      'kind': 'frame',
      'layout': picture['layout'],
      'gap': picture['gap'],
      'padding': picture['padding'],
      'mainAlign': picture['mainAlign'],
      'crossAlign': picture['crossAlign'],
      'children': children,
      'w': sizeToWire(r.width) ?? picture['w'],
      'h': r.height ?? picture['h'],
      if (r.fill == null && !r.hasFx('fill')) 'fill': picture['fill'],
      if (r.cornerRadius == 0) 'corner': picture['corner'],
      'opacity':
          (r.fxRendered('opacity') as double) *
          ((picture['opacity'] as num?)?.toDouble() ?? 1),
    };
  }

  Iterable<(SceneNode, int)> walk() sync* {
    Iterable<(SceneNode, int)> visit(SceneNode n, int depth) sync* {
      yield (n, depth);
      for (var c in n.children) {
        yield* visit(c, depth + 1);
      }
    }

    yield* visit(root, 0);
  }

  /// A fresh identifier-shaped name — names are field names in the file, so
  /// they must be unique and valid Dart identifiers from the moment a node is
  /// created, not sanitized at save time.
  String uniqueName(String base) {
    var taken = {for (var (n, _) in walk()) n.name};
    var i = 1;
    while (taken.contains('$base$i')) {
      i++;
    }
    return '$base$i';
  }

  /// The node declared under [name], or null — names are field names, so
  /// this is the resolution a motion target (`scene.headline`) performs.
  SceneNode? nodeNamed(String name) {
    for (var (node, _) in walk()) {
      if (node.name == name) return node;
    }
    return null;
  }

  FrameNode? parentOf(SceneNode node) {
    FrameNode? search(FrameNode frame) {
      if (frame.children.contains(node)) return frame;
      for (var c in frame.children.whereType<FrameNode>()) {
        var found = search(c);
        if (found != null) return found;
      }
      return null;
    }

    return search(root);
  }

  void delete(SceneNode node) {
    var parent = parentOf(node);
    if (parent == null) return;
    edit(() {
      parent.children.remove(node);
    });
  }

  void reorder(SceneNode node, int newIndex) {
    var parent = parentOf(node);
    if (parent == null) return;
    var index = parent.children.indexOf(node);
    var clamped = newIndex.clamp(0, parent.children.length - 1);
    if (index == clamped) return;
    edit(() {
      parent.children.removeAt(index);
      parent.children.insert(clamped, node);
    });
  }

  /// Topmost direct child of [scope] containing the point (artboard coords).
  SceneNode? hitShallow(double x, double y, {FrameNode? scope}) {
    var frame = scope ?? root;
    for (var c in frame.children.reversed) {
      var rect = c.measured;
      if (rect != null && rect.contains(x, y)) return c;
    }
    return null;
  }

  /// Deepest node under the point.
  SceneNode? hitDeep(double x, double y) {
    SceneNode? visit(SceneNode n) {
      var rect = n.measured;
      if (rect == null || !rect.contains(x, y)) return null;
      for (var c in n.children.reversed) {
        var hit = visit(c);
        if (hit != null) return hit;
      }
      return n == root ? null : n;
    }

    return visit(root);
  }

  /// The authored plane, captured: params and the node tree, deep-copied.
  /// The fx plane is NOT part of a snapshot — it is evaluated state owned
  /// by its writers, and restoring authored values must not cancel a
  /// playing motion (the same law as Save never reading fx).
  SceneSnapshot snapshot() =>
      SceneSnapshot._([...params], deepCopyNode(root) as FrameNode);

  /// Write [state] back into this document — the undo door's other half.
  /// Nodes are REVIVED, not replaced: a live node with the snapshot's name
  /// and kind gets the state copied into it and keeps its object identity,
  /// so fx writers (an [Effect], a bound motion), widget keys and anything
  /// else holding the node keep working across an undo. Only nodes the
  /// snapshot has and the document lost come back as fresh copies.
  void restore(SceneSnapshot state) {
    edit(() {
      params
        ..clear()
        ..addAll(state._params);
      var live = {for (var (n, _) in walk()) n.name: n};
      SceneNode revive(SceneNode snap) {
        var into = live[snap.name];
        if (into == null ||
            into.runtimeType != snap.runtimeType ||
            (into is ExternalNode &&
                into.entry != (snap as ExternalNode).entry) ||
            (into is SceneRefNode &&
                into.sceneClassName != (snap as SceneRefNode).sceneClassName)) {
          return deepCopyNode(snap);
        }
        switch ((into, snap)) {
          case (FrameNode i, FrameNode s):
            i
              ..layout = s.layout
              ..gap = s.gap
              ..padding = s.padding
              ..mainAlign = s.mainAlign
              ..crossAlign = s.crossAlign
              ..children.clear()
              ..children.addAll([for (var c in s.children) revive(c)]);
          case (TextNode i, TextNode s):
            i
              ..text = s.text
              ..fontSize = s.fontSize
              ..weight = s.weight
              ..color = s.color
              ..align = s.align
              ..maxLines = s.maxLines;
          case (ShapeNode i, ShapeNode s):
            i.circle = s.circle;
          case (ExternalNode i, ExternalNode s):
            i.args
              ..clear()
              ..addAll(s.args);
          case (SceneRefNode i, SceneRefNode s):
            i.args
              ..clear()
              ..addAll(s.args);
          default:
            throw StateError('unreachable: kinds matched above');
        }
        into
          ..x = snap.x
          ..y = snap.y
          ..width = snap.width
          ..height = snap.height
          ..fill = snap.fill
          ..borderColor = snap.borderColor
          ..borderWidth = snap.borderWidth
          ..cornerRadius = snap.cornerRadius
          ..opacity = snap.opacity
          ..paramRefs.clear()
          ..paramRefs.addAll(snap.paramRefs);
        return into;
      }

      revive(state._root);
    });
  }
}

/// The authored half of a document at one moment. Opaque: made by
/// [SceneDocument.snapshot], consumed by [SceneDocument.restore], reusable —
/// restoring copies out of it, never hands its own nodes over.
class SceneSnapshot {
  SceneSnapshot._(this._params, this._root);

  final List<SceneParamDecl> _params;
  final FrameNode _root;
}

/// A deep copy of [node]'s authored plane — every authored property,
/// paramRefs and children; never fx, measured geometry or the document
/// pointer. [rename] maps every name in the subtree (a duplicate needs
/// fresh names — names are field identity, unique per scene); a snapshot
/// passes nothing and keeps them.
SceneNode deepCopyNode(SceneNode node, {String Function(String)? rename}) {
  var name = rename == null ? node.name : rename(node.name);
  var copy = switch (node) {
    FrameNode f =>
      FrameNode(name, layout: f.layout)
        ..gap = f.gap
        ..padding = f.padding
        ..mainAlign = f.mainAlign
        ..crossAlign = f.crossAlign
        ..children.addAll([
          for (var c in f.children) deepCopyNode(c, rename: rename),
        ]),
    TextNode t =>
      TextNode(name, t.text)
        ..fontSize = t.fontSize
        ..weight = t.weight
        ..color = t.color
        ..align = t.align
        ..maxLines = t.maxLines,
    ShapeNode s => ShapeNode(name, circle: s.circle),
    ExternalNode e => ExternalNode(name, e.entry, args: Map.of(e.args)),
    // The instance is copied too, so the copy draws at once; each copy owns
    // its own, because args are applied by mutating it.
    SceneRefNode r =>
      SceneRefNode(name, r.sceneClassName, args: Map.of(r.args))
        ..instance = r.instance == null
            ? null
            : instantiateScene(r.instance!, r.args),
  };
  copy
    ..x = node.x
    ..y = node.y
    ..width = node.width
    ..height = node.height
    ..fill = node.fill
    ..borderColor = node.borderColor
    ..borderWidth = node.borderWidth
    ..cornerRadius = node.cornerRadius
    ..opacity = node.opacity
    ..paramRefs.addAll(node.paramRefs);
  return copy;
}
