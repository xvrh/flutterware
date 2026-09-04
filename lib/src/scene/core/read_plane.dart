// What a document that was READ needs, and a compiled one never touches.
//
// A `.scene.dart` class is Dart: `Invoice(number: 'INV-99')` sets a field
// and `late final invoiceNo = TextNode(number)` reads it, which is the whole
// of parameter substitution. This file is the same thing done by hand, for
// the one case where there is no constructor to do it — a document the tool
// PARSED from source, or decoded from the wire.
//
// So nothing here is on a shipped app's path. What a read document keeps to
// make it possible — [SceneNode.paramRefs], [SceneDocument.params] and its
// list table, [SceneRepeat.source] — is storage and stays declared with the
// nodes; the behaviour is all here.
//
// A part rather than its own library, because it works on the document's
// private state and the alternative is to widen that for the editor's sake.
part of 'model.dart';

/// The read plane: what a document with no constructor does instead of one.
extension SceneReadPlane on SceneDocument {
  /// The items a repeat over [param] draws: the argument if one was
  /// applied, otherwise the mockup the file declares.
  List<SceneItem> itemsOf(String param) =>
      _lists[param] ?? paramNamed(param)?.items ?? const [];

  /// Instantiate: set every parameter-bound property whose parameter is
  /// named in [args]. This is what the export matrix does per language and
  /// what a caller's arguments do at mount — the model-level half of
  /// `BannerScene(title: …)`.
  void applyArgs(Map<String, Object?> args) {
    edit(() {
      for (var p in params) {
        if (p.kind != SceneParamKind.list) continue;
        if (args[p.name] case List raw) {
          _lists[p.name] = [
            for (var item in raw) (item as Map).cast<String, Object>(),
          ];
        }
      }
      for (var (node, _) in walk()) {
        for (var entry in node.paramRefs.entries) {
          if (!args.containsKey(entry.value)) continue;
          setSceneProperty(node, entry.key, args[entry.value]);
        }
      }
      // A repeat over data that just changed is a new rule: rebuilt from
      // the recorded binding, template row included.
      bindRepeats(this);
    });
  }
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

/// Write one authored property by the name a [SceneNode.paramRefs] entry
/// keys it under. The one place that maps a property name to a slot, so an
/// argument and a repeated item's field land the same way.
void setSceneProperty(SceneNode node, String prop, Object? value) {
  switch (prop) {
    case 'x':
      node.x = (value! as num).toDouble();
    case 'y':
      node.y = (value! as num).toDouble();
    case 'width':
      node.width = sizeFromWire(value);
    case 'height':
      node.height = sizeFromWire(value);
    case 'corner':
      node.corner = (value! as num).toDouble();
    case 'opacity':
      node.opacity = (value! as num).toDouble();
    case 'fill':
      node.fill = value as SceneColor?;
    case 'text':
      // A number filling a text slot is ordinary in a repeated row — a
      // quantity is a number and reads as one, not as "12.0".
      (node as TextNode).text = switch (value) {
        double d when d == d.roundToDouble() && d.abs() < 1e15 =>
          '${d.round()}',
        _ => '$value',
      };
    case 'fontSize':
      (node as TextNode).fontSize = (value! as num).toDouble();
    case 'color':
      (node as TextNode).color = value! as SceneColor;
    case 'gap':
      (node as FrameNode).gap = (value! as num).toDouble();
    case 'padding':
      (node as FrameNode).padding = SceneEdges.all((value! as num).toDouble());
  }
}

/// Fill in one item's fields across a repeated subtree: every property
/// bound to `<list>.<field>` takes that field's value. Returns [node], so a
/// copy can be made and filled in one expression.
SceneNode applySceneItem(SceneNode node, String list, SceneItem item) {
  var prefix = '$list.';
  void visit(SceneNode n) {
    for (var ref in n.paramRefs.entries) {
      if (!ref.value.startsWith(prefix)) continue;
      var field = ref.value.substring(prefix.length);
      if (!item.containsKey(field)) continue;
      setSceneProperty(n, ref.key, item[field]);
    }
    n.children.forEach(visit);
  }

  visit(node);
  return node;
}

/// Rebuild the repeat closures of a document that was READ — parsed from
/// source, or decoded from JSON — rather than compiled.
///
/// A compiled scene's binding is the closure the file wrote. A read one has
/// only what the reader could record: which parameter the items came from,
/// and which property of which cell reads which field ([SceneNode.paramRefs],
/// spelled `<list>.<field>`). This turns that back into the same closure, so
/// there is one way to draw a repeat and not two.
///
/// Safe to call again whenever the items change or the tree is restored —
/// it rebinds rather than accumulating, and a closure that outlived its
/// node is exactly what a restore leaves behind.
void bindRepeats(SceneDocument doc) {
  for (var (node, _) in doc.walk()) {
    if (node is! FrameNode) continue;
    var source = node.repeated?.source;
    if (source == null || source.isEmpty) continue;
    var items = doc.itemsOf(source);
    node.repeated = SceneRepeat(
      items: items,
      source: source,
      // Read off the frame's LIVE cells, every time. They are not a
      // template beside the first row — they ARE the first row, so editing
      // one has to change every row and not just the one on screen.
      row: (item) => [
        for (var cell in node.children)
          applySceneItem(deepCopyNode(cell), source, item! as SceneItem),
      ],
    );
    // Which makes the first item's values belong ON those cells, written in
    // place so the objects the editor selected and the motion writes to are
    // the same ones afterwards.
    if (items.isNotEmpty) {
      for (var cell in node.children) {
        applySceneItem(cell, source, items.first);
      }
    }
  }
}

/// Record a repeat the way a reader can: the parameter it draws from, with
/// the cells already in place. [bindRepeats] turns it into the closure.
void recordRepeat(FrameNode frame, String source) {
  frame.repeated = SceneRepeat(items: const [], source: source, row: (_) => []);
}
