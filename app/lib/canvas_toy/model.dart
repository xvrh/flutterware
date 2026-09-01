// Disposable spike: the scene-canvas toy's model. A deliberately *uniform*
// node — every node carries the same styling bag (fill, corner, opacity) and
// the same geometry slots — to feel where the Figma-shaped model fits Flutter
// and where it fights it. Not a design; an instrument.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
/// Declared in the file as `this.<name> = <literal>` plus its
/// `final <Type> <name>;` field; referenced by node properties by bare
/// identifier. Parameters share the class namespace with node fields.
enum SceneParamKind { string, number, color }

class SceneParamDecl {
  SceneParamDecl(this.name, this.kind, this.defaultValue);

  final String name;
  final SceneParamKind kind;

  /// String, double or Color — the mockup, read by every consumer that
  /// passes no argument (the editor, the export matrix at the base point).
  final Object defaultValue;

  String get typeName => switch (kind) {
    SceneParamKind.string => 'String',
    SceneParamKind.number => 'double',
    SceneParamKind.color => 'Color',
  };
}

sealed class SceneNode {
  SceneNode(this.name);

  final String name;

  /// Measurement anchor: the editor reads laid-out geometry back from the
  /// render tree, because flex children have no authored position.
  final key = GlobalKey();

  // Authored geometry. x/y are meaningful only under an absolute parent;
  // null width/height means hug content.
  double x = 0;
  double y = 0;
  double? width;
  double? height;

  // The uniform styling bag — the bet under test.
  Color? fill;
  double cornerRadius = 0;
  double opacity = 1;

  /// Laid-out rect in artboard coordinates, swept after each frame.
  Rect? measured;

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
    'fill' => fill ?? const Color(0x00000000),
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
  double padding = 0;
  MainAxisAlignment mainAlign = MainAxisAlignment.start;
  CrossAxisAlignment crossAlign = CrossAxisAlignment.center;

  @override
  final List<SceneNode> children = [];

  @override
  String get typeName => 'Frame';
}

class TextNode extends SceneNode {
  TextNode(super.name, this.text);

  String text;
  double fontSize = 16;
  FontWeight weight = FontWeight.w400;
  Color color = const Color(0xFF1A1A1A);

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

class SceneDocument extends ChangeNotifier {
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
  /// fx writes of a frame into one notification, and make sure a frame is
  /// coming — a hidden or idle window schedules none on its own.
  void fxTick() {
    if (_fxScheduled) return;
    _fxScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _fxScheduled = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The scene's declared parameters, in declaration order.
  final params = <SceneParamDecl>[];

  SceneNode? selected;

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
              node.width = (v as num?)?.toDouble();
            case 'height':
              node.height = (v as num?)?.toDouble();
            case 'corner':
              node.cornerRadius = (v! as num).toDouble();
            case 'opacity':
              node.opacity = (v! as num).toDouble();
            case 'fill':
              node.fill = v as Color?;
            case 'text':
              (node as TextNode).text = v! as String;
            case 'fontSize':
              (node as TextNode).fontSize = (v! as num).toDouble();
            case 'color':
              (node as TextNode).color = v! as Color;
            case 'gap':
              (node as FrameNode).gap = (v! as num).toDouble();
            case 'padding':
              (node as FrameNode).padding = (v! as num).toDouble();
          }
        }
      }
    });
  }

  /// Bumped when a post-frame sweep finds moved geometry, so overlays repaint
  /// without rebuilding the scene.
  final geometryEpoch = ValueNotifier(0);

  void edit(void Function() fn) {
    fn();
    _adopt();
    notifyListeners();
  }

  /// The wire format the scene host renders from — data, never code. The
  /// wire is the PICTURE, so it carries rendered values (base op fx): a
  /// playing motion reaches the guest as a stream of these, one per flush.
  Map<String, dynamic> toJson() => {
    'root': _json(root),
    'selected': selected?.name,
  };

  Map<String, dynamic> _json(SceneNode n) {
    var tx = n.fxRendered('translateX') as double;
    var ty = n.fxRendered('translateY') as double;
    var scale = n.fxRendered('scale') as double;
    var rotate = n.fxRendered('rotate') as double;
    var fill = n.hasFx('fill') ? n.fxRendered('fill') as Color : n.fill;
    return {
      'name': n.name,
      'x': n.x,
      'y': n.y,
      'w': n.width,
      'h': n.height,
      'fill': fill?.toARGB32(),
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
          'padding': f.padding,
          'crossAlign': f.crossAlign.index,
          'children': [for (var c in f.children) _json(c)],
        },
        TextNode t => {
          'kind': 'text',
          'text': t.text,
          'fontSize': t.fxRendered('fontSize'),
          'weight': FontWeight.values.indexOf(t.weight),
          'color': (t.fxRendered('color') as Color).toARGB32(),
        },
        ShapeNode s => {'kind': 'shape', 'circle': s.circle},
        ExternalNode e => {
          'kind': 'ext',
          'entry': e.entry,
          'args': e.renderedArgs,
        },
      },
    };
  }

  void select(SceneNode? node) {
    if (selected != node) {
      selected = node;
      notifyListeners();
    }
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
      if (selected == node) selected = null;
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

  /// Nodes the canvas exposes to the pointer, bottom-to-top: top-level
  /// children always, plus the children of the selected node's frame chain.
  /// Selection determines hit-test structure — the click ladder is z-order.
  Iterable<SceneNode> addressable() {
    var seen = <SceneNode>{};
    var out = <SceneNode>[];
    void addAll(Iterable<SceneNode> nodes) {
      for (var n in nodes) {
        if (seen.add(n)) out.add(n);
      }
    }

    addAll(root.children);
    var sel = selected;
    if (sel != null) {
      var chain = <FrameNode>[];
      var p = parentOf(sel);
      while (p != null && p != root) {
        chain.insert(0, p);
        p = parentOf(p);
      }
      if (sel is FrameNode) chain.add(sel);
      for (var f in chain) {
        addAll(f.children);
      }
    }
    return out;
  }

  /// Topmost direct child of [scope] containing [point] (artboard coords).
  SceneNode? hitShallow(Offset point, {FrameNode? scope}) {
    var frame = scope ?? root;
    for (var c in frame.children.reversed) {
      var rect = c.measured;
      if (rect != null && rect.contains(point)) return c;
    }
    return null;
  }

  /// Deepest node under [point].
  SceneNode? hitDeep(Offset point) {
    SceneNode? visit(SceneNode n) {
      var rect = n.measured;
      if (rect == null || !rect.contains(point)) return null;
      for (var c in n.children.reversed) {
        var hit = visit(c);
        if (hit != null) return hit;
      }
      return n == root ? null : n;
    }

    return visit(root);
  }
}

/// The hard-coded "agent draft" of the coffee store banner: roughly right,
/// to be refined by direct manipulation.
SceneDocument coffeeBannerDraft() {
  var root = FrameNode('root')
    ..width = 1024
    ..height = 500
    ..fill = const Color(0xFF2B1B12);

  var glow = ShapeNode('glow', circle: true)
    ..x = 600
    ..y = -110
    ..width = 480
    ..height = 480
    ..fill = const Color(0xFF4A2F1F)
    ..opacity = 0.7;

  var cup = TextNode('cup', '☕')
    ..x = 690
    ..y = 110
    ..fontSize = 190;

  var headline = TextNode('headline', 'Fresh coffee, faster')
    ..fontSize = 54
    ..weight = FontWeight.w700
    ..color = Colors.white;

  var sub = TextNode('subtitle', 'Order ahead. Skip the line. Earn rewards.')
    ..fontSize = 20
    ..color = const Color(0xFFD8C9BD);

  var ctaLabel = TextNode('ctaLabel', 'Get the app')
    ..fontSize = 17
    ..weight = FontWeight.w600
    ..color = Colors.white;

  var cta = FrameNode('cta', layout: NodeLayout.row)
    ..padding = 16
    ..fill = const Color(0xFFE8632B)
    ..cornerRadius = 28;
  cta.children.add(ctaLabel);

  var copy = FrameNode('copy', layout: NodeLayout.column)
    ..x = 64
    ..y = 120
    ..width = 500
    ..gap = 16
    ..crossAlign = CrossAxisAlignment.start;
  copy.children.addAll([headline, sub, cta]);

  // External widgets — rendered as placeholders here, natively in the guest.
  var badge = ExternalNode('badge', 'DrinkBadge', args: {'size': 140.0})
    ..x = 560
    ..y = 290
    ..width = 140
    ..height = 140;
  var spinner = ExternalNode('loading', 'Spinner', args: {'size': 40.0})
    ..x = 950
    ..y = 430
    ..width = 40
    ..height = 40;
  var order = ExternalNode('order', 'OrderButton', args: {'label': 'Order now'})
    ..x = 830
    ..y = 400
    ..width = 150
    ..height = 44;

  root.children.addAll([glow, cup, copy, badge, spinner, order]);
  return SceneDocument(root);
}
