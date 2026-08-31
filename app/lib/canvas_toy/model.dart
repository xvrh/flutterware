// Disposable spike: the scene-canvas toy's model. A deliberately *uniform*
// node — every node carries the same styling bag (fill, corner, opacity) and
// the same geometry slots — to feel where the Figma-shaped model fits Flutter
// and where it fights it. Not a design; an instrument.
import 'package:flutter/material.dart';

enum NodeLayout { absolute, row, column }

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

  String get typeName;

  List<SceneNode> get children => const [];
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

  @override
  String get typeName => 'Ext';
}

class SceneDocument extends ChangeNotifier {
  SceneDocument(this.root);

  final FrameNode root;
  SceneNode? selected;

  /// Bumped when a post-frame sweep finds moved geometry, so overlays repaint
  /// without rebuilding the scene.
  final geometryEpoch = ValueNotifier(0);

  void edit(void Function() fn) {
    fn();
    notifyListeners();
  }

  /// The wire format the scene host renders from — data, never code.
  Map<String, dynamic> toJson() => {
    'root': _json(root),
    'selected': selected?.name,
  };

  Map<String, dynamic> _json(SceneNode n) => {
    'name': n.name,
    'x': n.x,
    'y': n.y,
    'w': n.width,
    'h': n.height,
    'fill': n.fill?.toARGB32(),
    'corner': n.cornerRadius,
    'opacity': n.opacity,
    ...switch (n) {
      FrameNode f => {
        'kind': 'frame',
        'layout': f.layout.name,
        'gap': f.gap,
        'padding': f.padding,
        'crossAlign': f.crossAlign.index,
        'children': [for (var c in f.children) _json(c)],
      },
      TextNode t => {
        'kind': 'text',
        'text': t.text,
        'fontSize': t.fontSize,
        'weight': FontWeight.values.indexOf(t.weight),
        'color': t.color.toARGB32(),
      },
      ShapeNode s => {'kind': 'shape', 'circle': s.circle},
      ExternalNode e => {'kind': 'ext', 'entry': e.entry, 'args': e.args},
    },
  };

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
  var root = FrameNode('Banner')
    ..width = 1024
    ..height = 500
    ..fill = const Color(0xFF2B1B12);

  var glow = ShapeNode('Glow', circle: true)
    ..x = 600
    ..y = -110
    ..width = 480
    ..height = 480
    ..fill = const Color(0xFF4A2F1F)
    ..opacity = 0.7;

  var cup = TextNode('Cup', '☕')
    ..x = 690
    ..y = 110
    ..fontSize = 190;

  var headline = TextNode('Headline', 'Fresh coffee, faster')
    ..fontSize = 54
    ..weight = FontWeight.w700
    ..color = Colors.white;

  var sub = TextNode('Subtitle', 'Order ahead. Skip the line. Earn rewards.')
    ..fontSize = 20
    ..color = const Color(0xFFD8C9BD);

  var ctaLabel = TextNode('CTA label', 'Get the app')
    ..fontSize = 17
    ..weight = FontWeight.w600
    ..color = Colors.white;

  var cta = FrameNode('CTA', layout: NodeLayout.row)
    ..padding = 16
    ..fill = const Color(0xFFE8632B)
    ..cornerRadius = 28;
  cta.children.add(ctaLabel);

  var copy = FrameNode('Copy', layout: NodeLayout.column)
    ..x = 64
    ..y = 120
    ..width = 500
    ..gap = 16
    ..crossAlign = CrossAxisAlignment.start;
  copy.children.addAll([headline, sub, cta]);

  // External widgets — rendered as placeholders here, natively in the guest.
  var badge = ExternalNode('Badge', 'DrinkBadge', args: {'size': 140.0})
    ..x = 560
    ..y = 290
    ..width = 140
    ..height = 140;
  var spinner = ExternalNode('Loading', 'Spinner', args: {'size': 40.0})
    ..x = 950
    ..y = 430
    ..width = 40
    ..height = 40;
  var order = ExternalNode('Order', 'OrderButton', args: {'label': 'Order now'})
    ..x = 830
    ..y = 400
    ..width = 150
    ..height = 44;

  root.children.addAll([glow, cup, copy, badge, spinner, order]);
  return SceneDocument(root);
}
