/// The widget tree of one entry, as it is carried between processes.
///
/// Plain Dart on purpose, exactly like `ui_catalog/knob.dart`: `fw` and the MCP
/// server link this and neither can reach `dart:ui`. The half that walks a live
/// tree lives in `guest_inspect.dart` and is the only Flutter in here.
library;

/// Where a widget's constructor was called.
///
/// Only ever present when the program was compiled with
/// `--track-widget-creation` — see `DaemonConfig.trackWidgetCreation`, which is
/// why it is on. The location is read out of the framework's inspector rather
/// than off the widget: the kernel transform stores it behind a private
/// interface in `package:flutter`, and Dart mangles private names per library,
/// so no code outside that library can name the field. Not even dynamically.
class InspectSource {
  const InspectSource({
    required this.file,
    required this.line,
    required this.column,
  });

  factory InspectSource.fromJson(Map<String, Object?> json) => InspectSource(
    file: json['file'] as String? ?? '',
    line: json['line'] as int? ?? 0,
    column: json['column'] as int? ?? 0,
  );

  /// A `file://` URI, as the framework reports it.
  final String file;
  final int line;
  final int column;

  /// `path/to/file.dart:12:5`, with [relativeTo] stripped when it matches.
  ///
  /// An absolute URI is the truth and a relative path is what anyone reading
  /// the output wants, so this keeps the first and prints the second.
  String describe({String? relativeTo}) {
    var path = Uri.tryParse(file)?.toFilePath() ?? file;
    if (relativeTo != null && path.startsWith(relativeTo)) {
      path = path.substring(relativeTo.length);
      if (path.startsWith('/')) path = path.substring(1);
    }
    return '$path:$line:$column';
  }

  Map<String, Object?> toJson() => {
    'file': file,
    'line': line,
    'column': column,
  };
}

/// Where a widget ended up and what it was allowed.
///
/// This is the half the inspector cannot answer. Its tree carries no geometry
/// at all, and `getLayoutExplorerNode` is one call per node — so a caller
/// asking "why is this zero-height" would pay a round trip per candidate.
/// Reading it off the [RenderObject] while the tree is being walked costs
/// nothing extra and puts the answer in the same node as the question.
class InspectLayout {
  const InspectLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.constraints,
    this.isRepaintBoundary = false,
    this.flex,
    this.flexFactor,
    this.flexFit,
  });

  factory InspectLayout.fromJson(Map<String, Object?> json) => InspectLayout(
    x: _double(json['x']),
    y: _double(json['y']),
    width: _double(json['width']),
    height: _double(json['height']),
    constraints: switch (json['constraints']) {
      Map c => InspectConstraints.fromJson(c.cast<String, Object?>()),
      _ => null,
    },
    isRepaintBoundary: json['repaintBoundary'] as bool? ?? false,
    flex: switch (json['flex']) {
      Map f => InspectFlex.fromJson(f.cast<String, Object?>()),
      _ => null,
    },
    flexFactor: json['flexFactor'] as int?,
    flexFit: json['flexFit'] as String?,
  );

  /// Position in the guest's own coordinates — the same space a capture is
  /// taken in, so a rect here crops that PNG without a transform.
  final double x;
  final double y;
  final double width;
  final double height;

  /// What the parent allowed. Half of every layout question is here rather
  /// than in [width] and [height]: a box that is 0 wide because it was given
  /// `maxWidth: 0` is a different bug from one that chose to be.
  final InspectConstraints? constraints;

  final bool isRepaintBoundary;

  /// Set when this node *is* a `Row`, `Column` or `Flex`.
  final InspectFlex? flex;

  /// Set when this node is a *child* of one — the `Expanded`/`Flexible` story,
  /// read off the parent data rather than off any widget.
  final int? flexFactor;

  /// `tight` or `loose`.
  final String? flexFit;

  Map<String, Object?> toJson() => {
    // Guarded for the same reason as the constraints, though a laid-out box
    // should never be non-finite: an encoder that throws takes down the whole
    // read, so nothing that reaches it is left to chance.
    'x': _finite(x),
    'y': _finite(y),
    'width': _finite(width),
    'height': _finite(height),
    if (constraints != null) 'constraints': constraints!.toJson(),
    if (isRepaintBoundary) 'repaintBoundary': true,
    if (flex != null) 'flex': flex!.toJson(),
    if (flexFactor != null) 'flexFactor': flexFactor,
    if (flexFit != null) 'flexFit': flexFit,
  };

  static double _double(Object? value) => switch (value) {
    num n => n.toDouble(),
    _ => 0,
  };

  static double _finite(double value) => value.isFinite ? value : 0;
}

/// What a parent allowed a child to be.
class InspectConstraints {
  const InspectConstraints({
    required this.minWidth,
    required this.maxWidth,
    required this.minHeight,
    required this.maxHeight,
  });

  factory InspectConstraints.fromJson(Map<String, Object?> json) =>
      InspectConstraints(
        minWidth: _in(json['minWidth']),
        maxWidth: _in(json['maxWidth']),
        minHeight: _in(json['minHeight']),
        maxHeight: _in(json['maxHeight']),
      );

  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;

  /// **Unbounded is `null`, not `Infinity`.** JSON has no infinity and
  /// `jsonEncode` throws on one, which is not a theoretical corner: an
  /// unbounded `maxWidth` is what most of a real tree is laid out under, so
  /// the first entry with a `Column` in it failed to encode at all.
  ///
  /// Null is unambiguous here because all four are always present — the
  /// constraints object either exists with every bound or does not exist.
  Map<String, Object?> toJson() => {
    'minWidth': _out(minWidth),
    'maxWidth': _out(maxWidth),
    'minHeight': _out(minHeight),
    'maxHeight': _out(maxHeight),
  };

  static Object? _out(double value) => value.isFinite ? value : null;

  static double _in(Object? value) => switch (value) {
    num n => n.toDouble(),
    // Absent means unbounded, per [toJson].
    _ => double.infinity,
  };

  /// `w 0..900, h 0..∞` — how a human reads it, and infinity written as
  /// something a terminal can print.
  String describe() =>
      'w ${_n(minWidth)}..${_n(maxWidth)}, h ${_n(minHeight)}..${_n(maxHeight)}';

  static String _n(double value) =>
      value.isInfinite ? '∞' : value.toStringAsFixed(1);
}

/// A `Row`, `Column` or `Flex`, as its children experience it.
class InspectFlex {
  const InspectFlex({
    required this.direction,
    this.mainAxisAlignment,
    this.crossAxisAlignment,
    this.mainAxisSize,
  });

  factory InspectFlex.fromJson(Map<String, Object?> json) => InspectFlex(
    direction: json['direction'] as String? ?? '',
    mainAxisAlignment: json['mainAxisAlignment'] as String?,
    crossAxisAlignment: json['crossAxisAlignment'] as String?,
    mainAxisSize: json['mainAxisSize'] as String?,
  );

  final String direction;
  final String? mainAxisAlignment;
  final String? crossAxisAlignment;
  final String? mainAxisSize;

  Map<String, Object?> toJson() => {
    'direction': direction,
    if (mainAxisAlignment != null) 'mainAxisAlignment': mainAxisAlignment,
    if (crossAxisAlignment != null) 'crossAxisAlignment': crossAxisAlignment,
    if (mainAxisSize != null) 'mainAxisSize': mainAxisSize,
  };
}

/// One widget in the tree.
class InspectNode {
  const InspectNode({
    required this.id,
    required this.type,
    this.description,
    this.source,
    this.createdByLocalProject = false,
    this.offstage = false,
    this.layout,
    this.children = const [],
  });

  factory InspectNode.fromJson(Map<String, Object?> json) => InspectNode(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? '',
    description: json['description'] as String?,
    createdByLocalProject: json['local'] as bool? ?? false,
    offstage: json['offstage'] as bool? ?? false,
    layout: switch (json['layout']) {
      Map layout => InspectLayout.fromJson(layout.cast<String, Object?>()),
      _ => null,
    },
    source: switch (json['source']) {
      Map<String, Object?> source => InspectSource.fromJson(source),
      Map source => InspectSource.fromJson(source.cast<String, Object?>()),
      _ => null,
    },
    children: [
      for (var child in json['children'] as List? ?? const [])
        InspectNode.fromJson((child as Map).cast<String, Object?>()),
    ],
  );

  /// The node's identity, and the whole reason this type exists rather than
  /// the inspector's JSON being passed through.
  ///
  /// **Derived from the tree's shape, never assigned.** The framework's ids
  /// (`inspector-42`) are minted per object group, refcounted, and die with the
  /// process — which is fatal here, because every `fw` invocation and every MCP
  /// call opens a fresh session and holds nothing. An agent that reads a tree
  /// in one process and asks about a node in the next has to be talking about
  /// the same node, and only a derived id can promise that.
  ///
  /// The form is the child-index path from the subtree root: `''` for the root,
  /// then `0`, `0/1`, `0/1/2`. Stable as long as the tree is, which is the most
  /// any structural id can offer — see [InspectTree.nodeAt] for what a caller
  /// gets when it is not.
  final String id;

  /// The widget's runtime type — `Padding`, `_Dashboard`.
  final String type;

  /// The framework's own one-line description, which carries more than the
  /// type: `Text("Save")`, `SizedBox(width: 8.0)`. Null when it says nothing
  /// the type does not.
  final String? description;

  final InspectSource? source;

  /// Whether this widget is in the tree but not on the screen.
  ///
  /// True for content nobody can see or touch: a route kept alive under the
  /// one that covers it, an `Offstage`/`Visibility(visible: false)` subtree,
  /// the hidden children of an `IndexedStack`. Such nodes keep their
  /// last-laid-out [layout] — **stale rects that overlap the visible screen**
  /// — which is why [InspectTree.nodeAtPoint] skips them and the tree view
  /// folds them away by default. See `guest_inspect.dart` for how it is
  /// detected; the VM-service path (`run`) cannot detect it and leaves this
  /// false.
  final bool offstage;

  /// Whether the framework considers this the user's code rather than
  /// `package:flutter`'s.
  ///
  /// This is what "summary tree" means, and it is decided by [source] — so
  /// without creation tracking it is false for everything and a summary tree
  /// is byte-for-byte the full one. Measured: `dashboard` is 695 nodes either
  /// way with tracking off, and 51 with it on.
  final bool createdByLocalProject;

  /// Where it ended up, when it has a box.
  ///
  /// Null for a widget with no [RenderObject] of its own — a provider, a
  /// builder — which is most of a summary tree. That is why it is nullable
  /// rather than zero-filled: "it has no box" and "its box is empty" are
  /// different answers and only one of them is a bug.
  final InspectLayout? layout;

  final List<InspectNode> children;

  /// This node and everything under it, depth-first, with offstage subtrees
  /// folded to their flagged top node — reported, so a reader knows the
  /// content exists, and cut there, because a covered route is most of a
  /// tree's bulk and none of its picture.
  ///
  /// The fold does not apply when this node is itself offstage: whoever
  /// starts a walk *at* hidden content has asked about it.
  Iterable<InspectNode> get nodesFoldingOffstage =>
      _foldingOffstage(parentOffstage: offstage);

  Iterable<InspectNode> _foldingOffstage({required bool parentOffstage}) sync* {
    yield this;
    if (offstage && !parentOffstage) return;
    for (var child in children) {
      yield* child._foldingOffstage(parentOffstage: offstage);
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    if (description != null) 'description': description,
    if (source != null) 'source': source!.toJson(),
    'local': createdByLocalProject,
    // Sparse: nearly every node is on stage, and the flag is only news when
    // it is true.
    if (offstage) 'offstage': true,
    if (layout != null) 'layout': layout!.toJson(),
    if (children.isNotEmpty)
      'children': [for (var child in children) child.toJson()],
  };
}

/// One entry's tree, as of one build of it.
class InspectTree {
  const InspectTree({required this.entryId, required this.root});

  factory InspectTree.fromJson(Map<String, Object?> json) => InspectTree(
    entryId: json['entry'] as String?,
    root: switch (json['root']) {
      Map root => InspectNode.fromJson(root.cast<String, Object?>()),
      _ => null,
    },
  );

  static const empty = InspectTree(entryId: null, root: null);

  /// Which entry this is of.
  ///
  /// The same warning as `KnobReport.entryId`: a tree naming another entry is
  /// a read that landed before the switch did, not an empty one.
  final String? entryId;

  /// Null when the guest has not built yet — a headless host draws nothing
  /// until a frame is asked for, so a tree read before one is an answer about
  /// nothing rather than an error.
  final InspectNode? root;

  /// Every node, depth-first, root included.
  Iterable<InspectNode> get nodes sync* {
    Iterable<InspectNode> walk(InspectNode node) sync* {
      yield node;
      for (var child in node.children) {
        yield* walk(child);
      }
    }

    if (root case var root?) yield* walk(root);
  }

  /// [nodes], minus offstage subtrees — pruned at the flagged node rather than
  /// filtered per node, because a subtree's descendants do not repeat the flag.
  Iterable<InspectNode> get _onstage sync* {
    Iterable<InspectNode> walk(InspectNode node) sync* {
      if (node.offstage) return;
      yield node;
      for (var child in node.children) {
        yield* walk(child);
      }
    }

    if (root case var root?) yield* walk(root);
  }

  int get length => nodes.length;

  /// The deepest node whose box contains ([x], [y]), in the guest's own
  /// coordinates.
  ///
  /// **An approximation of a hit test, and deliberately one.** It knows only
  /// rectangles: not transforms, not clips, not opacity, not `IgnorePointer`,
  /// and of two overlapping boxes at the same depth it takes the later, which
  /// is a guess at paint order rather than knowledge of it.
  ///
  /// That is the right trade for a *pointer*. Following the mouse means
  /// answering every frame, where a round trip per move would stutter and being
  /// one node out for a moment costs nothing. Anything that has to be right —
  /// what a click actually selected — asks the guest, which runs the
  /// framework's own `hitTest` over the real render tree.
  ///
  /// Nodes with no box are skipped rather than treated as empty: a provider or
  /// a builder lays nothing out, and its child is the thing under the cursor.
  /// Every node is considered rather than only the children of one that
  /// contains the point, because a child can be laid out beyond its parent —
  /// which is what an overflow *is*, and overflowing widgets are exactly the
  /// ones somebody is pointing at.
  ///
  /// Offstage nodes are skipped too, subtree and all: a route kept alive under
  /// the current one holds its old rects, which overlap the screen — and being
  /// deeper, they *won* here, so picking on a screenshot could select a widget
  /// from the previous screen. What is not on the picture cannot be what the
  /// pointer means.
  InspectNode? nodeAtPoint(double x, double y) {
    InspectNode? best;
    var bestDepth = -1;
    for (var node in _onstage) {
      var layout = node.layout;
      if (layout == null) continue;
      if (x < layout.x || y < layout.y) continue;
      if (x >= layout.x + layout.width || y >= layout.y + layout.height) {
        continue;
      }
      // `>=` rather than `>`: depth-first order visits later siblings last, so
      // ties go to whichever was drawn on top.
      var depth = node.id.isEmpty ? 0 : node.id.split('/').length;
      if (depth >= bestDepth) {
        best = node;
        bestDepth = depth;
      }
    }
    return best;
  }

  /// The node with [id], or null.
  ///
  /// Null rather than a nearest match on purpose. A structural id points at a
  /// position, and a caller that edited the demo between two calls is asking
  /// about a position that may now hold something else — answering with
  /// whatever moved into it would be a confident wrong answer. The caller
  /// re-reads the tree.
  InspectNode? nodeAt(String id) {
    for (var node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  Map<String, Object?> toJson() => {'entry': entryId, 'root': root?.toJson()};
}
