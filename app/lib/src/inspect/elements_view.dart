import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog_guest.dart';

import '../address/address_scope.dart';
import 'inspect_dock.dart';
import '../ui/theme.dart';

/// Tree on the left, the selected node's detail on the right — the Elements
/// tab of an [InspectDock], shared verbatim between the UI catalog's live
/// tree and a scenario step's snapshot. It renders an [InspectNode] and
/// neither knows nor cares which of the two produced it.
///
/// Selection is the `node` address parameter, read and written here: the
/// catalog and the step page use the same name, so a link with a node in it
/// means the same thing on both pages.
class ElementsView extends StatefulWidget {
  const ElementsView({
    super.key,
    required this.root,
    required this.placeholder,
    required this.highlight,
    required this.displayRoot,
  });

  /// The tree, or null while the host has nothing — the [placeholder] says
  /// why.
  final InspectNode? root;

  /// What an empty view says: "Reading the tree…", "No entry selected" — the
  /// host knows, this widget only shows it.
  final String placeholder;

  /// Set as the pointer runs down the rows, so the surface above draws the
  /// box for whatever is under it; read as well, so the row lights up when
  /// the *picker* is what put it there.
  final ValueNotifier<String?> highlight;

  /// What a source path is shortened against.
  final String displayRoot;

  @override
  State<ElementsView> createState() => _ElementsViewState();
}

class _ElementsViewState extends State<ElementsView> {
  /// The tree's share of the width. The detail pane is the narrower of the
  /// two because a tree row is wide by nature — type, description, box and
  /// source all read on one line — while a detail is a short column of pairs.
  double _split = 0.62;

  @override
  Widget build(BuildContext context) {
    var root = widget.root;
    if (root == null) {
      return Container(
        color: context.colors.panel,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          widget.placeholder,
          textAlign: TextAlign.center,
          style: context.type.caption.copyWith(color: context.colors.mut),
        ),
      );
    }

    var selectedId = AddressScope.params(context)['node'];
    var selected = selectedId == null
        ? null
        : InspectTree(entryId: null, root: root).nodeAt(selectedId);

    // Its own (invisible) Material: the tree rows are `InkWell`s, and this was
    // inheriting one from [InspectDock] purely because both hosts happened to
    // put it there. The run cockpit uses it outside a dock, which is where a
    // borrowed ancestor stops arriving.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var treeWidth = (constraints.maxWidth * _split)
              .clamp(200.0, math.max(200.0, constraints.maxWidth - 220))
              .toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: treeWidth,
                child: _TreeView(
                  root: root,
                  selectedId: selectedId,
                  highlight: widget.highlight,
                ),
              ),
              InspectSplitGrip(
                axis: Axis.vertical,
                onDrag: (delta) => setState(() {
                  _split = ((treeWidth + delta) / constraints.maxWidth).clamp(
                    0.2,
                    0.85,
                  );
                }),
              ),
              Expanded(
                child: _Detail(
                  node: selected,
                  selectedId: selectedId,
                  displayRoot: widget.displayRoot,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TreeView extends StatefulWidget {
  const _TreeView({
    required this.root,
    required this.selectedId,
    required this.highlight,
  });

  final InspectNode root;
  final String? selectedId;

  /// Set as the pointer runs down the rows, so the preview draws the box for
  /// whatever is under it. Cleared when the pointer leaves the list — a
  /// highlight that outlived the hover would be pointing at nothing.
  final ValueNotifier<String?> highlight;

  @override
  State<_TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends State<_TreeView> {
  static const _rowHeight = 22.0;

  final _closed = <String>{};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TreeView old) {
    super.didUpdateWidget(old);
    var id = widget.selectedId;
    if (id != null && id != old.selectedId) _reveal(id);
  }

  /// Unfolds whatever was hiding [id] and scrolls it into view.
  ///
  /// The picker can land three levels inside a folded subtree and below the
  /// scroll, and selecting a row somewhere the asker cannot see is answering
  /// the question into the void. Chrome brings the tree to the element; so
  /// does this.
  void _reveal(String id) {
    var parts = id.isEmpty ? const <String>[] : id.split('/');
    var opened = false;
    // Every ancestor, root first: '' then '0' then '0/1' for '0/1/2'.
    for (var i = 0; i <= parts.length - 1; i++) {
      if (_closed.remove(parts.take(i).join('/'))) opened = true;
    }
    if (opened) setState(() {});

    // After the frame, so the rows reflect whatever was just unfolded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      var index = _rows().indexWhere((row) => row.$1.id == id);
      if (index < 0) return;
      var offset = index * _rowHeight;
      var top = _scroll.offset;
      var bottom = top + _scroll.position.viewportDimension - _rowHeight;
      // Only when it is actually out of sight: scrolling a row that was
      // already visible moves the tree under the reader for no reason.
      if (offset < top || offset > bottom) {
        _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
      }
    });
  }

  /// The visible rows, flattened, with the depth each should be drawn at.
  List<(InspectNode, int)> _rows() {
    var rows = <(InspectNode, int)>[];
    void walk(InspectNode node, int depth) {
      rows.add((node, depth));
      if (_closed.contains(node.id)) return;
      for (var child in node.children) {
        walk(child, depth + 1);
      }
    }

    walk(widget.root, 0);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    var rows = _rows();

    return Container(
      color: context.colors.panel,
      child: LayoutBuilder(
        builder: (context, constraints) => MouseRegion(
          onExit: (_) => widget.highlight.value = null,
          child: ListView.builder(
            primary: false,
            controller: _scroll,
            itemCount: rows.length,
            itemExtent: _rowHeight,
            itemBuilder: (context, index) {
              var (node, depth) = rows[index];
              return _TreeRow(
                node: node,
                depth: depth,
                // Measured once for the list rather than per row: it is the
                // panel's width, and the panel does not change width between
                // two rows of the same frame.
                indent: math.min(depth * 12.0, constraints.maxWidth * 0.4),
                // Below this there is no room for it and the type, and the
                // type is what you scan by.
                showSize: constraints.maxWidth > 320,
                highlight: widget.highlight,
                open: !_closed.contains(node.id),
                selected: node.id == widget.selectedId,
                onHover: (over) {
                  if (over) {
                    widget.highlight.value = node.id;
                  } else if (widget.highlight.value == node.id) {
                    // Only if it is still ours: the pointer has already
                    // entered the next row by the time this fires, and
                    // clearing then would put out the light that row just
                    // turned on.
                    widget.highlight.value = null;
                  }
                },
                onToggle: () => setState(() {
                  if (!_closed.remove(node.id)) _closed.add(node.id);
                }),
                onTap: () =>
                    AddressScope.write(context).setParam('node', node.id),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.indent,
    required this.showSize,
    required this.open,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.onHover,
    required this.highlight,
  });

  final InspectNode node;
  final int depth;

  /// How far the row is pushed in, **capped**: twelve levels at twelve pixels
  /// each is most of a narrow panel, and an indent that eats the whole row is
  /// what put Flutter's overflow stripes across an inspector.
  final double indent;

  /// Whether there is room for the box on the right.
  final bool showSize;
  final bool open;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  /// Read as well as written, so the row lights up for whatever the rectangle
  /// is currently on — including when the *picker* is what put it there.
  /// Sweep the demo and the tree follows you, which is the same courtesy in
  /// reverse.
  final ValueNotifier<String?> highlight;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return InkWell(
      onTap: onTap,
      onHover: onHover,
      child: ValueListenableBuilder(
        valueListenable: highlight,
        builder: (context, lit, child) => Container(
          // Selection outranks hover: one is where you are, the other is
          // where you were going.
          color: selected
              ? colors.accentSoft
              : lit == node.id
              ? colors.panel2
              : null,
          child: child,
        ),
        child: Container(
          padding: EdgeInsets.only(left: FwSpacing.sm + indent),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: node.children.isEmpty
                    ? null
                    : InkWell(
                        onTap: onToggle,
                        child: Icon(
                          open ? Icons.arrow_drop_down : Icons.arrow_right,
                          size: 14,
                          color: colors.mut,
                        ),
                      ),
              ),
              // **One flexible child, not two beside a `Spacer`.** Three flex
              // children divide the free space between them, so the spacer
              // was taking a third of every row — which both truncated the
              // description early, against an obviously empty right margin,
              // and left the size wherever the description happened to stop.
              // The text takes everything that is going; the size is a
              // column.
              Expanded(
                child: Row(
                  children: [
                    // The type keeps what it needs and the description gives
                    // way: a deep node indents its row a long way, and the
                    // type is what you scan by.
                    Flexible(
                      child: Text(
                        node.type,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: context.type.caption.copyWith(
                          // The demo's own widgets bright, the plumbing
                          // between them dim: a summary tree is mostly the
                          // former, and the few that are not are what you
                          // scroll past.
                          color: node.createdByLocalProject
                              ? colors.ink
                              : colors.mut,
                        ),
                      ),
                    ),
                    if (node.description case var description?
                        when description != node.type) ...[
                      const SizedBox(width: FwSpacing.sm),
                      Flexible(
                        child: Text(
                          description,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: context.type.caption.copyWith(
                            color: colors.mut2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showSize)
                // A fixed width and right-aligned, so the numbers form a
                // column rather than each landing where its row's text ran
                // out. Present even when the node has no box, or the rows
                // either side of one would close the gap and the column would
                // wander again.
                SizedBox(
                  width: 84,
                  child: Padding(
                    padding: const EdgeInsets.only(right: FwSpacing.md),
                    child: Text(
                      switch (node.layout) {
                        var l? => '${_n(l.width)}×${_n(l.height)}',
                        null => '',
                      },
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: context.type.micro.copyWith(color: colors.mut3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What is known about one node.
class _Detail extends StatelessWidget {
  const _Detail({
    required this.node,
    required this.selectedId,
    required this.displayRoot,
  });

  final InspectNode? node;

  /// What a source path is shortened against.
  final String displayRoot;

  /// Told apart from [node] being null: an id that resolves to nothing is a
  /// selection that outlived the tree it named, which is worth saying rather
  /// than showing as "nothing selected".
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    if (node == null) {
      return Container(
        color: context.colors.panel2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          selectedId == null
              ? 'Select a widget'
              : 'The tree no longer has $selectedId.\nIt named a position, and '
                    'the shape changed.',
          textAlign: TextAlign.center,
          style: context.type.caption.copyWith(color: colors.mut),
        ),
      );
    }

    var it = node!;
    var layout = it.layout;
    return Container(
      color: colors.panel2,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(FwSpacing.lg),
        children: [
          SelectableText(
            it.type,
            style: context.type.bodyStrong.copyWith(color: colors.ink),
          ),
          if (it.description case var description? when description != it.type)
            SelectableText(
              description,
              style: context.type.caption.copyWith(color: colors.mut),
            ),
          const SizedBox(height: FwSpacing.md),
          // The id is the thing an agent is handed and the thing it hands
          // back — `screenshot --node`, `tree --node` — so it is selectable
          // rather than decorative.
          _Pair(label: 'id', value: it.id.isEmpty ? '(root)' : it.id),
          if (it.source case var source?)
            _Pair(
              label: 'source',
              // Shortened against the worktree, so this is the same string
              // `fw run ui_catalog inspect --tree` prints for the same node —
              // one can be pasted where the other was expected.
              value: source.describe(relativeTo: displayRoot),
            ),
          if (layout != null) ...[
            const SizedBox(height: FwSpacing.md),
            _Pair(
              label: 'size',
              value: '${_n(layout.width)} × ${_n(layout.height)}',
            ),
            _Pair(label: 'offset', value: '${_n(layout.x)}, ${_n(layout.y)}'),
            if (layout.constraints case var constraints?)
              _Pair(label: 'given', value: constraints.describe()),
            if (layout.flex case var flex?)
              _Pair(
                label: 'flex',
                value: [
                  flex.direction,
                  ?flex.mainAxisAlignment,
                  ?flex.crossAxisAlignment,
                  ?flex.mainAxisSize,
                ].join(', '),
              ),
            if (layout.flexFactor case var factor?)
              _Pair(
                label: 'in parent',
                value: layout.flexFit == null
                    ? 'flex $factor'
                    : 'flex $factor (${layout.flexFit})',
              ),
            if (layout.isRepaintBoundary)
              _Pair(label: 'paints', value: 'repaint boundary'),
          ] else ...[
            const SizedBox(height: FwSpacing.md),
            Text(
              // Not zero-filled, because "it has no box" and "its box is
              // empty" are different answers and only one of them is a bug.
              'Lays nothing out of its own — a provider or a builder.',
              style: context.type.caption.copyWith(color: colors.mut),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FwSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: context.type.micro.copyWith(color: context.colors.mut3),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: context.type.caption.copyWith(color: context.colors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout arrives as doubles and is nearly always whole pixels, so `48` beats
/// `48.0` and `47.5` still says so.
String _n(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);
