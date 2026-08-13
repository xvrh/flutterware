import 'dart:convert';
import 'dart:developer' as developer;

// `rendering` as well as `widgets`, for the layout half: `widgets.dart`
// re-exports a curated slice of rendering that has `RenderFlex` in it and not
// `FlexParentData`, and the parent data is where a child's flex actually
// lives. Still no `material` — a guest should not have to link Material to be
// inspectable.
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'node.dart';
import 'semantics.dart';
import 'semantics_capture.dart';

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
    developer.registerExtension('ext.flutterware.semantics', (_, args) async {
      switch (args['on']) {
        case 'true':
          enableSemantics(true);
        case 'false':
          enableSemantics(false);
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode(readSemantics().toJson()),
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
  ///
  /// [filter] narrows what comes back and nothing else — the walk is the same
  /// walk, because the ids have to keep meaning positions in the whole tree.
  /// Unfiltered by default, which is what the inspect panel and the previews
  /// client have always been handed; the drive loop is the caller that asks
  /// for less.
  InspectTree read({InspectFilter? filter}) {
    var tree = _build().tree;
    return filter == null ? tree : tree.filtered(filter);
  }

  /// The handle that keeps semantics on while somebody is looking.
  ///
  /// A live app has semantics **off** — unlike `testWidgets`, which holds a
  /// handle by default — and building the tree costs every frame, so it runs
  /// only between the panel opening the Semantics tab and closing it. Held
  /// here rather than in the extension closure so [enableSemantics] is
  /// callable in-process too.
  SemanticsHandle? _semantics;

  /// Turns the semantics tree on or off.
  ///
  /// Idempotent both ways. Turning on schedules a frame, because the tree is
  /// built *by* a frame and an idle guest would otherwise never produce one —
  /// the read polls until it appears.
  void enableSemantics(bool on) {
    if (on) {
      if (_semantics != null) return;
      _semantics = SemanticsBinding.instance.ensureSemantics();
      SchedulerBinding.instance.ensureVisualUpdate();
    } else {
      _semantics?.dispose();
      _semantics = null;
    }
  }

  /// The semantics tree, as `semantics_capture.dart` shapes it.
  ///
  /// The entry id is withheld until there is a tree, so a poll settling on
  /// the id keeps waiting through the frame that builds it rather than
  /// accepting "nothing yet" as this entry's answer.
  InspectSemantics readSemantics() {
    var root = captureSemanticsTree();
    return InspectSemantics(
      entryId: root == null ? null : entryIdOf(),
      root: root,
    );
  }

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
  static String? _preview(Element? element) => switch (element) {
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
    // Resolved once for the three readers below: the id round-trips through
    // the inspector's object registry, which is not free per node.
    var element = _elementOf(json);
    var render = element?.renderObject;
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
      description:
          _preview(element) ?? (description == type ? null : description),
      createdByLocalProject: json['createdByLocalProject'] as bool? ?? false,
      offstage: offstage,
      properties: _propertiesOf(element?.widget),
      source: switch (json['creationLocation']) {
        Map location => InspectSource.fromJson(
          location.cast<String, Object?>(),
        ),
        _ => null,
      },
      layout: _layoutOf(render),
      label: _labelOf(render),
      selected: _selectedOf(render),
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

  /// What [widget] says about itself, filtered to what a reader would keep.
  ///
  /// The framework's diagnostics are written for dumps and are mostly noise
  /// at a detail pane's distance, so three cuts: only `DiagnosticLevel.info`
  /// and up (`fine` is `dependencies: [MediaQuery]` and friends), the value
  /// itself cut down by [shortenPropertyValue] (a colour to its hex, a
  /// `TextStyle`'s paragraph to its head), and at most twelve per node. The
  /// walk pays this on every node of every read — measured before keeping,
  /// like the semantics capture before it: +168µs on the shop tree's 1.5ms
  /// read, +6KB on its 37KB JSON (see the consolidation spec).
  static Map<String, String> _propertiesOf(Widget? widget) {
    if (widget == null) return const {};
    var properties = <String, String>{};
    for (var property in widget.toDiagnosticsNode().getProperties()) {
      if (property.isFiltered(DiagnosticLevel.info)) continue;
      var name = property.name;
      if (name == null) continue;
      // The one named exception: every `Text` inlines its style's
      // diagnostics, and `inherit: true` is the resting state of every style
      // — a property that appears on every text node distinguishes none.
      if (name == 'inherit') continue;
      var value = property.toDescription();
      if (value.isEmpty || value == 'null') continue;
      properties[name] = shortenPropertyValue(value);
      if (properties.length >= 12) break;
    }
    return properties;
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

/// The semantics node [render] contributes to, or null.
///
/// **Up the render tree, never by comparing rectangles.** A widget with no
/// semantics of its own is inside somebody's, so the walk climbs until it finds
/// one — which is exact, and cheap because the render object is already in
/// hand. The rectangle alternative was tried and is wrong in both directions:
/// a `Checkbox`'s node is smaller than the `CheckboxListTile` that owns it and
/// a `Tab`'s is 9.5× larger than the `Tab` widget, so a containment test
/// reported that Flutter publishes no tab selection. It does. Measured 60 of 60
/// controls matched this way — see the S6 spike findings.
///
/// Null outside debug mode and whenever the app holds no `SemanticsHandle`;
/// both are absences rather than answers, which is why [InspectNode.selected]
/// is a tri-state.
SemanticsNode? _semanticsOf(RenderObject? render) {
  var at = render;
  while (at != null) {
    if (at.debugSemantics case var node?) return node;
    at = at.parent;
  }
  return null;
}

/// This widget's own accessibility label — **no climbing.**
///
/// The two fields want different walks, and running one for both was a bug
/// worth recording. Semantics merges: a header wrapped in `MergeSemantics`
/// owns one node whose label is every string under it concatenated, and its
/// descendants own nothing. Climbing from a `Text` in that header therefore
/// returns the *whole header* as that text's label — measured live, eight
/// different texts on one screen all reporting
/// `"Changes / …/ Watching / 14 files / +583 / …"`.
///
/// A label describes the thing it is on, so it is read off the render object
/// itself or not at all. A widget with nothing of its own falls through to the
/// words inside it, which is what [Screen] does next and what the Brewline
/// cards needed anyway. [_selectedOf] still climbs, because a selection state
/// genuinely belongs to the control above: a `Tab`'s flags live on the tab's
/// semantics node, not on the `Tab` widget's 38pt label box.
/// Down, not up, and only when the answer is unambiguous: the *one* semantics
/// node in this widget's subtree, when there is exactly one.
///
/// This is what a `TextField` needs. Its hint is built by the framework's own
/// internals, so it is not in the summary tree and no roll-up can reach it —
/// measured, `find "Filter"` matches nothing on a screen with a "Filter paths"
/// field on it — but the `EditableText` inside does publish it. One node in
/// the subtree is that widget describing itself through a child. Two or more
/// is a container, and the roll-up is the honest answer there.
///
/// Bounded on both counts, because this runs per node of every read: it stops
/// at the second node it finds and six render objects down.
String? _labelOf(RenderObject? render) {
  if (render == null) return null;
  var own = render.debugSemantics?.getSemanticsData().label;
  if (own != null && own.isNotEmpty) return own;

  SemanticsNode? only;
  var many = false;
  void descend(RenderObject node, int depth) {
    if (many || depth > 6) return;
    node.visitChildren((child) {
      if (many) return;
      if (child.debugSemantics case var semantics?) {
        if (only != null) {
          many = true;
          return;
        }
        only = semantics;
        return;
      }
      descend(child, depth + 1);
    });
  }

  descend(render, 0);
  if (many || only == null) return null;
  var label = only!.getSemanticsData().label;
  return label.isEmpty ? null : label;
}

/// Whether this is the current one of its group: true, false, or *nothing
/// said*. See [InspectNode.selected] for why the third state is load-bearing.
bool? _selectedOf(RenderObject? render) {
  var data = _semanticsOf(render)?.getSemanticsData();
  if (data == null) return null;
  var flags = data.flagsCollection.toStrings().toSet();
  if (flags.contains('isSelected') ||
      flags.contains('isChecked') ||
      flags.contains('isToggled')) {
    return true;
  }
  if (flags.contains('hasSelectedState') ||
      flags.contains('hasCheckedState') ||
      flags.contains('hasToggledState')) {
    return false;
  }
  return null;
}

/// The geometry of one render object, or null when it has none to report.
///
/// Null rather than zeroes for a widget with no box of its own, and null for
/// one that has not been laid out: a size read before layout is not a size, it
/// is whatever was there last time.
InspectLayout? _layoutOf(RenderObject? render) {
  if (render is! RenderBox || !render.hasSize) return null;
  // The whole rect through the transform, not an origin from `localToGlobal`
  // beside a raw `render.size`. Those two are in different spaces the moment
  // any ancestor scales — a preview stage fitting a device to its pane, the
  // shell scaling itself below its minimum window size — and mixing them
  // reports a box whose position is on screen and whose size is not. Every
  // number a reader compares (a centre against `at "x,y"`, a width against the
  // screenshot) then quietly disagrees with the picture.
  var bounds = MatrixUtils.transformRect(
    render.getTransformTo(null),
    Offset.zero & render.size,
  );
  return InspectLayout(
    x: bounds.left,
    y: bounds.top,
    width: bounds.width,
    height: bounds.height,
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
