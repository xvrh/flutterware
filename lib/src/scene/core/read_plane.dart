// What a document that was READ needs, and a compiled one never touches.
//
// A `.scene.dart` class is Dart: `Invoice(number: 'INV-99')` sets a field
// and `late final invoiceNo = TextNode(number)` reads it, which is the whole
// of parameter substitution. This file is the same thing done by hand, for
// the one case where there is no constructor to do it — a document the tool
// PARSED from source, or decoded from the wire.
//
// So nothing here is on a shipped app's path. What a read document keeps to
// make it possible — [SceneNode.bindings], [SceneDocument.params] and its
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
        for (var entry in node.bindings.entries) {
          // An item binding takes its value from the repeat, below.
          if (entry.value case ParamRef(:var name)
              when args.containsKey(name)) {
            setSceneProperty(node, entry.key, args[name]);
          }
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
/// declarations and bindings, so it can take new args later.
SceneDocument instantiateScene(
  SceneDocument template,
  Map<String, Object?> args,
) {
  var doc = SceneDocument(deepCopyNode(template.root) as FrameNode)
    ..params.addAll(template.params);
  doc.applyArgs(args);
  return doc;
}

/// Read one authored property by the name a [SceneNode.bindings] entry keys
/// it under — the inverse of [setSceneProperty], and the same table.
Object? getSceneProperty(SceneNode node, String prop) => switch (prop) {
  'x' => node.x,
  'y' => node.y,
  'width' => sizeToWire(node.width),
  'height' => sizeToWire(node.height),
  'corner' => node.corner,
  'opacity' => node.opacity,
  'visible' => node.visible,
  'fill' => node.fill,
  'text' => (node as TextNode).text,
  'fontSize' => (node as TextNode).fontSize,
  'color' => (node as TextNode).color,
  'gap' => (node as FrameNode).gap,
  'padding' => (node as FrameNode).padding.left,
  _ => null,
};

/// The parameter kind [prop] of [node] can read, or null when the property
/// cannot be bound — the same table as [getSceneProperty] and
/// [setSceneProperty], seen as types.
SceneParamKind? bindableKind(SceneNode node, String prop) => switch (prop) {
  'x' ||
  'y' ||
  'width' ||
  'height' ||
  'corner' ||
  'opacity' => SceneParamKind.number,
  'fill' => SceneParamKind.color,
  'visible' => SceneParamKind.bool,
  'text' when node is TextNode => SceneParamKind.string,
  'fontSize' when node is TextNode => SceneParamKind.number,
  'color' when node is TextNode => SceneParamKind.color,
  'gap' || 'padding' when node is FrameNode => SceneParamKind.number,
  _ => null,
};

/// Write one authored property by the name a [SceneNode.bindings] entry
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
    case 'visible':
      node.visible = value! as bool;
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
  void visit(SceneNode n) {
    for (var ref in n.bindings.entries) {
      if (ref.value case ItemRef(list: var l, :var field) when l == list) {
        if (item.containsKey(field)) setSceneProperty(n, ref.key, item[field]);
      }
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
/// and which property of which cell reads which field ([SceneNode.bindings],
/// an [ItemRef]). This turns that back into the same closure, so
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

/// Route every edit of a bound property to what it is bound to — the other
/// half of a binding, run by the editor after each mutation.
///
/// The default IS the mockup: dragging a text whose `x` reads `slide` is
/// editing `slide`, because that is the value every caller who passes
/// nothing will get. So a node whose value has moved off its parameter's
/// default moves the default, and every other node reading that parameter
/// follows. For an item binding the default is the FIRST item's field, which
/// is the rule the whole repeater rests on; the rows are then redrawn.
///
/// A binding whose source is gone — a parameter no longer declared, an item
/// field no longer carried, a cell dragged out of the repeat it reads from —
/// is removed here, in the same edit, rather than dropped silently at save.
/// Returns the names of the properties whose binding was removed, so the
/// editor can say so.
List<String> reconcileBindings(SceneDocument doc) {
  var dropped = <String>[];
  var listChanged = false;
  for (var (node, _) in doc.walk()) {
    for (var entry in node.bindings.entries.toList()) {
      var prop = entry.key;
      var current = getSceneProperty(node, prop);
      // A property that was cleared — a fill removed, a size set to hug —
      // no longer reads anything.
      if (current == null) {
        node.bindings.remove(prop);
        dropped.add('${node.name}.$prop');
        continue;
      }
      switch (entry.value) {
        case ParamRef(:var name):
          var decl = doc.paramNamed(name);
          if (decl == null || decl.kind == SceneParamKind.list) {
            node.bindings.remove(prop);
            dropped.add('${node.name}.$prop');
          } else if (decl.defaultValue != current) {
            var i = doc.params.indexOf(decl);
            doc.params[i] = decl.withDefault(current);
            for (var (other, _) in doc.walk()) {
              if (identical(other, node)) continue;
              for (var e in other.bindings.entries) {
                if (e.value == entry.value) {
                  setSceneProperty(other, e.key, current);
                }
              }
            }
          }
        case ItemRef(:var list, :var field):
          var decl = doc.paramNamed(list);
          var scope = _repeatScope(doc, node);
          var items = decl?.items ?? const <SceneItem>[];
          if (decl == null ||
              decl.kind != SceneParamKind.list ||
              scope != list ||
              items.isEmpty ||
              !items.first.containsKey(field)) {
            node.bindings.remove(prop);
            dropped.add('${node.name}.$prop');
          } else {
            var was = items.first[field]!;
            var next = _itemValue(was, current);
            if (next != was) {
              var i = doc.params.indexOf(decl);
              doc.params[i] = decl.withDefault([
                {...items.first, field: next},
                ...items.skip(1),
              ]);
              listChanged = true;
            }
          }
      }
    }
  }
  if (listChanged) bindRepeats(doc);
  return dropped;
}

/// The list parameter of the nearest repeated frame enclosing [node], or
/// null when no repeat draws it — the scope inside which an [ItemRef] means
/// something.
String? _repeatScope(SceneDocument doc, SceneNode node) {
  for (var f = doc.parentOf(node); f != null; f = doc.parentOf(f)) {
    if (f.repeated?.source case var source? when source.isNotEmpty) {
      return source;
    }
  }
  return null;
}

/// What an edited cell writes back into its item: the field keeps its kind.
/// A quantity that was a number stays a number when the text still reads as
/// one, and a text that was `12` and became `12` again is unchanged.
Object _itemValue(Object was, Object current) {
  if (was is double && current is String) {
    var n = double.tryParse(current);
    if (n != null) return n;
  }
  if (was is String && current is double) {
    return current == current.roundToDouble() && current.abs() < 1e15
        ? '${current.round()}'
        : '$current';
  }
  return current;
}
