import 'dart:convert';
import 'dart:developer' as developer;

// `rendering` as well as `widgets`, for the layout half: `widgets.dart`
// re-exports a curated slice of rendering that has `RenderFlex` in it and not
// `FlexParentData`, and the parent data is where a child's flex actually
// lives. Still no `material` — a guest should not have to link Material to be
// inspectable.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'node.dart';

/// Reads the live widget tree out of a running guest.
///
/// **The structure and the source locations come from the framework's own
/// inspector, and everything else is ours.** That split is forced rather than
/// chosen: `--track-widget-creation` stores a widget's location behind
/// `_HasCreationLocation`, a private interface in `package:flutter`, and Dart
/// mangles private names per library — so no code here can read it, by
/// language rule rather than by omission. `WidgetInspectorService` is the only
/// thing that can, and [WidgetInspectorService.getRootWidgetSummaryTree] is
/// how it hands the value out.
///
/// What we keep is the part that matters across processes: the identity. The
/// inspector's ids are per-object-group and die with the process; ours are
/// derived from the tree's shape, so a tree read by one `fw` invocation can be
/// asked about by the next. See [InspectNode.id].
class GuestInspector {
  GuestInspector({required this.rootOf, required this.entryIdOf});

  /// The element the reported tree should start at — the demo, rather than the
  /// catalog chrome above it.
  ///
  /// A function because the subtree is remounted on every entry switch, so
  /// anything holding an [Element] would be holding the previous entry's.
  final Element? Function() rootOf;

  final String? Function() entryIdOf;

  /// Registers the extensions. Call once, before `runApp`, beside the knobs and
  /// axes ones — an extension has to outlive every entry switch.
  void registerExtensions() {
    developer.registerExtension('ext.flutterware.tree', (_, _) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(read().toJson()),
      );
    });
    developer.registerExtension('ext.flutterware.hitTest', (_, args) async {
      var x = double.tryParse(args['x'] ?? '');
      var y = double.tryParse(args['y'] ?? '');
      if (x == null || y == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          jsonEncode({'error': 'x and y are required, as numbers'}),
        );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ids': hitTest(x, y)}),
      );
    });
  }

  /// The tree as of the last build.
  ///
  /// Always the *summary* tree — the widgets the framework attributes to the
  /// user's code. There is deliberately no "give me everything" here, and the
  /// reason is worth recording because it looks like an omission: of the two
  /// public in-process readers, [WidgetInspectorService.getRootWidgetSummaryTree]
  /// returns a whole tree and `getRootWidget` returns the root and one level.
  /// The unfiltered whole tree is reachable only through the *service
  /// extension*, over a socket, from another process.
  ///
  /// So a `full` option here could only have been a filter over an
  /// already-filtered list — which is to say, a parameter that reads as a
  /// capability and does nothing. It was written that way first and measured:
  /// 44 nodes either way, zero of them non-local. If the whole tree is ever
  /// wanted it is a host-side call and its own decision.
  InspectTree read() => _build().tree;

  /// The nodes under a point, outermost first.
  ///
  /// Answers "what is at these pixels", which is one question asked by two
  /// callers: a panel turning a click into a selection, and an agent turning a
  /// screenshot into a node id. Both get the *chain* rather than the innermost
  /// hit, because the useful answer is usually a few levels out — the thing
  /// under the cursor is a `RenderParagraph` and the thing you meant is the
  /// button around it.
  ///
  /// [x] and [y] are in the guest's own coordinates, the same space
  /// [InspectLayout.x] reports and a capture is taken in.
  List<String> hitTest(double x, double y) {
    var (:tree, :byRenderObject) = _build();
    if (tree.root == null) return const [];
    var root = rootOf()?.renderObject;
    if (root is! RenderBox || !root.hasSize) return const [];

    var result = BoxHitTestResult();
    root.hitTest(result, position: root.globalToLocal(Offset(x, y)));

    // Innermost first out of the framework, and reversed on the way out: a
    // caller reading a chain wants it the way the tree reads.
    var ids = <String>[];
    for (var entry in result.path) {
      var id = byRenderObject[entry.target];
      // The hit path is render objects, and most of them belong to widgets no
      // summary tree mentions. Those are not "no answer", they are the
      // framework's internals, so they are skipped rather than reported.
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    return ids.reversed.toList();
  }

  /// The render object [id] names, or null when this tree has no such node.
  ///
  /// The expensive direction, and deliberately not offered as something to call
  /// often: it costs a whole summary-tree walk, because an id *is* a position
  /// in the summary tree and nothing cheaper knows where that is. [GuestWatch]
  /// calls it once when the selection changes and holds the result — which is
  /// only safe because it also drops it whenever the shape moves.
  ///
  /// The map is keyed the other way round because the hit test needs it that
  /// way, and inverting a few dozen entries here beats building both.
  RenderObject? renderObjectFor(String id) {
    var (:tree, :byRenderObject) = _build();
    if (tree.root == null) return null;
    for (var entry in byRenderObject.entries) {
      if (entry.value == id) return entry.key;
    }
    return null;
  }

  ({InspectTree tree, Map<RenderObject, String> byRenderObject}) _build() {
    var entryId = entryIdOf();
    var byRenderObject = <RenderObject, String>{};
    // A group name of our own: the inspector refcounts these and the panel or
    // DevTools may be holding others against the same isolate.
    const group = 'flutterware.inspect';
    try {
      var decoded = jsonDecode(
        WidgetInspectorService.instance.getRootWidgetSummaryTree(group),
      );
      if (decoded is! Map) {
        return (
          tree: InspectTree(entryId: entryId, root: null),
          byRenderObject: byRenderObject,
        );
      }
      var json = decoded.cast<String, Object?>();
      var demo = _findPreview(json) ?? json;
      // The marker is ours, added so this could find the demo at all. Reporting
      // it would be reporting the observer: a caller would see a root whose
      // source is a file inside `package:flutterware` and reasonably wonder
      // what it had to do with their demo. It always has exactly one child.
      if (_elementOf(demo) == rootOf()) {
        if (demo['children'] case [Map only, ...]) {
          demo = only.cast<String, Object?>();
        }
      }
      return (
        tree: InspectTree(
          entryId: entryId,
          root: _convert(demo, '', byRenderObject, null, false),
        ),
        byRenderObject: byRenderObject,
      );
    } finally {
      // Always: a group that outlives the read pins every Element in it, and
      // this runs on a live app rather than a debugger's breakpoint.
      //
      // `@protected` here means "reach these through the service extensions",
      // which is advice for a debugger talking over the VM service. We are
      // inside the guest, and going out to our own isolate over a socket to
      // ask it something it can answer synchronously would be the strange
      // choice. Same for `toObject` below.
      // ignore: invalid_use_of_protected_member
      WidgetInspectorService.instance.disposeGroup(group);
    }
  }

  /// The shallowest inspector node at or below the demo's root.
  ///
  /// Found by identity rather than by matching descriptions: every node in the
  /// JSON carries a `valueId`, and [WidgetInspectorService.toObject] turns that
  /// back into the very [DiagnosticsNode] it was made from. So this compares
  /// elements, not strings.
  ///
  /// It asks "at or below" rather than "is" because the marker itself need not
  /// be *in* the summary tree. A summary tree contains what the framework
  /// considers the user's code, and that verdict moves: today the marker
  /// qualifies because it is not in `package:flutter`, but a caller that
  /// narrows the pub roots to the project would drop it — and the demo below
  /// it would still be there. Matching on ancestry survives that; matching on
  /// the node itself would silently stop trimming.
  ///
  /// Null when nothing below the marker is in the tree, in which case the
  /// caller reports the whole thing: a tree with catalog chrome on top beats
  /// no tree.
  Map<String, Object?>? _findPreview(Map<String, Object?> json) {
    var marker = rootOf();
    if (marker == null) return null;

    Map<String, Object?>? search(Map<String, Object?> node) {
      if (_elementOf(node) case var element?) {
        if (_isAtOrBelow(element, marker)) return node;
      }
      for (var child in node['children'] as List? ?? const []) {
        if (child is! Map) continue;
        var hit = search(child.cast<String, Object?>());
        if (hit != null) return hit;
      }
      return null;
    }

    return search(json);
  }

  static bool _isAtOrBelow(Element element, Element marker) {
    if (identical(element, marker)) return true;
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (!identical(ancestor, marker)) return true;
      found = true;
      return false;
    });
    return found;
  }

  /// The words a node puts on screen, when it puts any there.
  ///
  /// The summary tree describes a `Text` as `Text` and nothing more — the
  /// framework's richer `Text("Save")` form comes from `withPreviews`, which is
  /// only reachable through the service extension. So this reads the widget
  /// itself, which is public API and exact.
  ///
  /// It is what makes searching by the words on screen work at all. Without it
  /// `find --query=Save` matches nothing, because no node's type or description
  /// has ever contained "Save" — which is the first thing anybody would try.
  /// [Text] only, deliberately. `Tooltip` and the rest of the labelled widgets
  /// live in `package:flutter/material.dart`, and this file imports `widgets`
  /// so that a guest is not made to link Material to be inspected.
  String? _preview(Map<String, Object?> json) => switch (_elementOf(json)) {
    Element(widget: Text(:var data?)) => 'Text("$data")',
    _ => null,
  };

  Element? _elementOf(Map<String, Object?> node) {
    var id = node['valueId'];
    if (id is! String) return null;
    // ignore: invalid_use_of_protected_member
    var object = WidgetInspectorService.instance.toObject(id);
    return switch (object) {
      DiagnosticsNode(value: Element element) => element,
      Element element => element,
      _ => null,
    };
  }

  /// One inspector node and its children, in our shape, with [path] as the id.
  ///
  /// [ancestorRender] and [ancestorOffstage] carry the nearest converted
  /// ancestor's render object and verdict, so each render edge is judged once
  /// on the way down rather than re-climbed per node — and a subtree under an
  /// offstage ancestor is marked without climbing at all.
  InspectNode _convert(
    Map<String, Object?> json,
    String path,
    Map<RenderObject, String> byRenderObject,
    RenderObject? ancestorRender,
    bool ancestorOffstage,
  ) {
    var children = json['children'] as List? ?? const [];
    var description = json['description'] as String?;
    var type = json['widgetRuntimeType'] as String? ?? description ?? '';
    var render = _elementOf(json)?.renderObject;
    if (render != null) {
      // First writer wins. Several widgets in a summary tree can share one
      // render object — a `Padding` under a `Semantics` under a builder all
      // report the same box — and the outermost is the one a click means.
      byRenderObject.putIfAbsent(render, () => path);
    }
    var offstage =
        ancestorOffstage ||
        (render != null && !_shown(render, upTo: ancestorRender));
    return InspectNode(
      id: path,
      type: type,
      // Only when it says more than the type does. `Text("Save")` earns its
      // place; a `Padding` described as "Padding" is the type twice.
      description: _preview(json) ?? (description == type ? null : description),
      createdByLocalProject: json['createdByLocalProject'] as bool? ?? false,
      offstage: offstage,
      source: switch (json['creationLocation']) {
        Map location => InspectSource.fromJson(
          location.cast<String, Object?>(),
        ),
        _ => null,
      },
      layout: _layoutOf(render),
      children: [
        for (var (index, child) in children.indexed)
          if (child is Map)
            _convert(
              child.cast<String, Object?>(),
              path.isEmpty ? '$index' : '$path/$index',
              byRenderObject,
              render ?? ancestorRender,
              offstage,
            ),
      ],
    );
  }

  /// Whether [render] is actually shown, judged over the render chain up to
  /// (and excluding) [upTo] — the nearest converted ancestor's render object.
  ///
  /// **The oracle is `visitChildrenForSemantics`.** The summary tree keeps the
  /// user's widgets and drops the framework's, and the framework's is where
  /// all the hiding happens — `_RenderTheater` skipping the routes a pushed
  /// screen covers, `RenderOffstage`, `RenderIndexedStack` showing one child
  /// of several. So the marker never survives into the tree, only the hidden
  /// content does, wearing rects from the last time it was laid out. What
  /// every one of those hiders has in common is that it also keeps the hidden
  /// child out of the semantics walk, by overriding this exact method — it is
  /// the same mechanism that keeps a covered route out of a screen reader.
  ///
  /// The known exceptions — the classes that skip the semantics walk while
  /// still painting the child — are exempted by type. All four are public,
  /// and the list was taken from the SDK's overrides, not guessed (see
  /// `2026-08-10-inspect-consolidation.md`).
  static bool _shown(RenderObject render, {required RenderObject? upTo}) {
    var node = render;
    while (!identical(node, upTo)) {
      var parent = node.parent;
      if (parent == null) break;
      if (!_visitsForSemantics(parent, node)) return false;
      node = parent;
    }
    return true;
  }

  static bool _visitsForSemantics(RenderObject parent, RenderObject child) {
    // Semantics-excluded but painted: skipping the semantics walk is these
    // classes' entire job, and their child is on screen all the same.
    if (parent is RenderExcludeSemantics ||
        parent is RenderIgnorePointer ||
        parent is RenderAbsorbPointer ||
        parent is RenderSliverIgnorePointer ||
        parent is SemanticsAnnotationsMixin) {
      return true;
    }
    var found = false;
    parent.visitChildrenForSemantics((visited) {
      if (identical(visited, child)) found = true;
    });
    return found;
  }
}

/// The geometry of one render object, or null when it has none to report.
///
/// Null rather than zeroes for a widget with no box of its own, and null for
/// one that has not been laid out: a size read before layout is not a size, it
/// is whatever was there last time.
InspectLayout? _layoutOf(RenderObject? render) {
  if (render is! RenderBox || !render.hasSize) return null;
  var origin = render.localToGlobal(Offset.zero);
  return InspectLayout(
    x: origin.dx,
    y: origin.dy,
    width: render.size.width,
    height: render.size.height,
    constraints: InspectConstraints(
      minWidth: render.constraints.minWidth,
      maxWidth: render.constraints.maxWidth,
      minHeight: render.constraints.minHeight,
      maxHeight: render.constraints.maxHeight,
    ),
    isRepaintBoundary: render.isRepaintBoundary,
    flex: switch (render) {
      RenderFlex flex => InspectFlex(
        direction: flex.direction.name,
        mainAxisAlignment: flex.mainAxisAlignment.name,
        crossAxisAlignment: flex.crossAxisAlignment.name,
        mainAxisSize: flex.mainAxisSize.name,
      ),
      _ => null,
    },
    // Read off the parent data rather than off a widget, because that is where
    // it lives: `Expanded` is a widget that writes a number onto its child.
    flexFactor: switch (render.parentData) {
      FlexParentData(:var flex) => flex,
      _ => null,
    },
    flexFit: switch (render.parentData) {
      FlexParentData(fit: var fit?) => fit.name,
      _ => null,
    },
  );
}
