// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';

/// Why the pixels differ, in words.
///
/// The pixel channel says *38% of this picture changed*; an agent cannot act
/// on that and a human cannot tell whether it is the point. This says
/// `Padding.all 12→20`, and it is what turns a heatmap into a sentence.
///
/// Nodes are matched by **shape, not by index**. A node's id is its
/// child-index path, so inserting one widget renumbers every sibling after it
/// and a diff keyed on ids reports the whole subtree as replaced. Children are
/// aligned by signature instead — the same longest-common-subsequence the
/// scenario flow uses on steps, for the same reason.
class TreeDiff {
  const TreeDiff(this.deltas);

  final List<TreeDelta> deltas;

  bool get isEmpty => deltas.isEmpty;

  static TreeDiff of(InspectNode? base, InspectNode? head) {
    var deltas = <TreeDelta>[];
    if (base == null && head == null) return const TreeDiff([]);
    if (base == null) {
      deltas.add(TreeDelta.added(_label(head!), head.type));
    } else if (head == null) {
      deltas.add(TreeDelta.removed(_label(base), base.type));
    } else {
      _walk(base, head, '', deltas, ancestorResized: false);
    }
    deltas.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return TreeDiff(deltas);
  }

  static void _walk(
    InspectNode base,
    InspectNode head,
    String path,
    List<TreeDelta> deltas, {
    required bool ancestorResized,
  }) {
    var here = path.isEmpty ? _label(head) : '$path › ${_label(head)}';
    var resized = false;

    if (base.description != head.description) {
      deltas.add(
        TreeDelta(
          kind: TreeDeltaKind.changed,
          path: here,
          property: 'description',
          base: base.description,
          head: head.description,
        ),
      );
    }

    var (a, b) = (base.layout, head.layout);
    if (a != null && b != null) {
      if (a.width != b.width || a.height != b.height) {
        resized = true;
        deltas.add(
          TreeDelta(
            kind: TreeDeltaKind.changed,
            path: here,
            property: 'size',
            base: _size(a),
            head: _size(b),
          ),
        );
      }
      if (a.x != b.x || a.y != b.y) {
        // A node that moved because something above it grew did not itself
        // change, and reporting it as one buries the node that did under
        // everything below it on the screen.
        deltas.add(
          TreeDelta(
            kind: ancestorResized
                ? TreeDeltaKind.shifted
                : TreeDeltaKind.changed,
            path: here,
            property: 'offset',
            base: _offset(a),
            head: _offset(b),
          ),
        );
      }
      if (_constraints(a) != _constraints(b)) {
        deltas.add(
          TreeDelta(
            kind: TreeDeltaKind.changed,
            path: here,
            property: 'constraints',
            base: _constraints(a),
            head: _constraints(b),
          ),
        );
      }
    }

    for (var pair in _fuse(
      _align(_onstage(base.children), _onstage(head.children)),
    )) {
      switch (pair) {
        case (var only?, null):
          deltas.add(TreeDelta.removed('$here › ${_label(only)}', only.type));
        case (null, var only?):
          deltas.add(TreeDelta.added('$here › ${_label(only)}', only.type));
        case (var left?, var right?):
          _walk(
            left,
            right,
            here,
            deltas,
            ancestorResized: ancestorResized || resized,
          );
        case _:
          break;
      }
    }
  }

  /// A change on a covered route is not a change to this step: a scenario
  /// that pushes a screen keeps the one beneath it alive in the tree, so
  /// diffing offstage subtrees flags every step after the push for a change
  /// only the earlier step shows. Pruning each side independently keeps the
  /// asymmetric case: a subtree offstage on one side only is unmatched, and
  /// reads as the addition or removal it visibly is.
  static List<InspectNode> _onstage(List<InspectNode> children) => [
    for (var child in children)
      if (!child.offstage) child,
  ];

  /// Pairs children up, longest common subsequence over their signatures.
  ///
  /// An unmatched left is a removal and an unmatched right an addition, which
  /// is the whole reason this is not a `zip`: one inserted `Padding` would
  /// otherwise pair every later sibling with the wrong node and report a tree
  /// full of changes.
  static List<(InspectNode?, InspectNode?)> _align(
    List<InspectNode> base,
    List<InspectNode> head,
  ) {
    var lengths = List.generate(
      base.length + 1,
      (_) => List.filled(head.length + 1, 0),
    );
    for (var i = base.length - 1; i >= 0; i--) {
      for (var j = head.length - 1; j >= 0; j--) {
        lengths[i][j] = _signature(base[i]) == _signature(head[j])
            ? lengths[i + 1][j + 1] + 1
            : (lengths[i + 1][j] > lengths[i][j + 1]
                  ? lengths[i + 1][j]
                  : lengths[i][j + 1]);
      }
    }

    var pairs = <(InspectNode?, InspectNode?)>[];
    var (i, j) = (0, 0);
    while (i < base.length && j < head.length) {
      if (_signature(base[i]) == _signature(head[j])) {
        pairs.add((base[i++], head[j++]));
      } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
        pairs.add((base[i++], null));
      } else {
        pairs.add((null, head[j++]));
      }
    }
    while (i < base.length) {
      pairs.add((base[i++], null));
    }
    while (j < head.length) {
      pairs.add((null, head[j++]));
    }
    return pairs;
  }

  /// Takes back the unambiguous half of what [_signature] gives up.
  ///
  /// An unmatched node is reported and then **not walked** — `_walk` recurses
  /// into matched pairs only — so a signature miss on a container hides every
  /// real change beneath it. Where a run of leftovers holds exactly one node
  /// on each side and the two are the same kind of widget, there is only one
  /// thing that can have happened to it, and pairing them turns
  /// `- Text("Save") / + Text("Pay")` into `description Save→Pay` with the
  /// subtree underneath still examined.
  ///
  /// One-to-one only, same type, same key. Two same-type leftovers on a side
  /// is a real ambiguity and guessing which is which is the nonsense
  /// [_signature] exists to refuse. A differing key is not an ambiguity at
  /// all — it is the author saying these are two different widgets, and it is
  /// the one thing this must never fuse across, or the split above buys
  /// nothing.
  static List<(InspectNode?, InspectNode?)> _fuse(
    List<(InspectNode?, InspectNode?)> pairs,
  ) {
    var fused = <(InspectNode?, InspectNode?)>[];
    var run = <(InspectNode?, InspectNode?)>[];

    void flush() {
      if (run.length > 1) {
        var lefts = [for (var (left, _) in run) ?left];
        var rights = [for (var (_, right) in run) ?right];
        if (lefts.length == 1 &&
            rights.length == 1 &&
            lefts.single.type == rights.single.type &&
            lefts.single.widgetKey == rights.single.widgetKey) {
          fused.add((lefts.single, rights.single));
          run.clear();
          return;
        }
      }
      fused.addAll(run);
      run.clear();
    }

    for (var pair in pairs) {
      if (pair.$1 == null || pair.$2 == null) {
        run.add(pair);
      } else {
        flush();
        fused.add(pair);
      }
    }
    flush();
    return fused;
  }

  /// What makes two nodes "the same node" across two runs.
  ///
  /// A key that [_names] its widget wins outright. It is the author's own
  /// statement of which widget this is — the whole reason the framework has
  /// keys — and it survives a re-worded label, a changed property and a moved
  /// sibling, none of which a description does.
  ///
  /// Otherwise the description. Type alone pairs the wrong `Text` in a column
  /// of them; the description carries the content — `Text("Save")` — so it
  /// separates them, at the cost of reporting a re-worded label as a removal
  /// plus an addition rather than a change. That is the right way round: a
  /// diff that pairs two different widgets reports nonsense about both. What
  /// softens the cost is [_fuse], which takes the unambiguous half of it back.
  static String _signature(InspectNode node) => switch (node.widgetKey) {
    var key? when _names(key) => '${node.type} key $key',
    _ => '${node.type} is ${node.description ?? ''}',
  };

  /// Whether a key says *which* widget this is, or only that there is one.
  ///
  /// A key with no value of its own is the same string on every node once its
  /// identity hash goes — every `GlobalKey()` in the tree is `[GlobalKey#]`,
  /// every `UniqueKey()` is `[#]`. It must therefore never displace the
  /// description in [_signature]: two sibling `Text`s given a `GlobalKey`
  /// each would otherwise share one signature, and deleting the first would
  /// align the second against it and report the wrong node as removed — a
  /// diff made *worse* by keys than it was without them.
  static bool _names(String key) => !key.endsWith('#]');

  /// `Text("Save")`, or `Form-[<'draft'>]`, or `Padding`.
  ///
  /// The key is spelled back on the way out — the framework's own `type-key`
  /// — because it is the name a reader would use for that node, and because
  /// two sibling `Form`s in a path are otherwise indistinguishable.
  static String _label(InspectNode node) =>
      node.description ??
      switch (node.widgetKey) {
        // A key that distinguishes nothing is a string the path would repeat
        // on every line of the report — see [_names].
        var key? when _names(key) => '${node.type}-$key',
        _ => node.type,
      };

  static String _size(InspectLayout layout) =>
      '${_number(layout.width)}×${_number(layout.height)}';

  static String _offset(InspectLayout layout) =>
      '${_number(layout.x)},${_number(layout.y)}';

  static String? _constraints(InspectLayout layout) {
    var c = layout.constraints;
    if (c == null) return null;
    return 'w ${_number(c.minWidth)}..${_number(c.maxWidth)}, '
        'h ${_number(c.minHeight)}..${_number(c.maxHeight)}';
  }

  static String _number(double value) {
    if (!value.isFinite) return '∞';
    return value == value.roundToDouble()
        ? '${value.round()}'
        : value.toStringAsFixed(1);
  }
}

/// One thing that is not the same about the two trees.
class TreeDelta {
  const TreeDelta({
    required this.kind,
    required this.path,
    this.property,
    this.base,
    this.head,
  });

  static TreeDelta fromJson(Map<String, Object?> json) => TreeDelta(
    kind:
        TreeDeltaKind.values.asNameMap()[json['kind']] ?? TreeDeltaKind.changed,
    path: json['path'] as String? ?? '',
    property: json['property'] as String?,
    base: json['base'] as String?,
    head: json['head'] as String?,
  );

  TreeDelta.added(this.path, String type)
    : kind = TreeDeltaKind.added,
      property = null,
      base = null,
      head = type;

  TreeDelta.removed(this.path, String type)
    : kind = TreeDeltaKind.removed,
      property = null,
      base = type,
      head = null;

  final TreeDeltaKind kind;

  /// Where in the tree, as widget names — `Column › Card › Padding`. Not the
  /// node id, which is a child-index path and means nothing to a reader.
  final String path;

  final String? property;
  final String? base;
  final String? head;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'path': path,
    'property': ?property,
    'base': ?base,
    'head': ?head,
  };

  @override
  String toString() => switch (kind) {
    TreeDeltaKind.added => '+ $path',
    TreeDeltaKind.removed => '- $path',
    _ => '$path $property $base→$head',
  };
}

/// Declared in the order a report ranks them.
enum TreeDeltaKind {
  added,
  removed,
  changed,

  /// A node whose box moved because an ancestor's did. Reported, because it
  /// explains why a picture differs far below the thing that actually
  /// changed — and demoted, because it is a consequence rather than a cause.
  shifted,
}
