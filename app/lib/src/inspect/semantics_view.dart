import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'inspect_dock.dart';
import 'semantics_node.dart';

/// The Semantics tab: what a screen reader gets, in reading order on the
/// left, one node's full reading on the right — the same tree-beside-detail
/// shape as `ElementsView`, so the two tabs read as one surface. Each row
/// lights its rect up on the picture — a scenario step's screenshot, or the
/// catalog's live preview; the view neither knows nor cares which.
///
/// Selection is **local state, not the address**: a semantics node has no id
/// space of its own yet, and the picker stays bound to Elements (see
/// `2026-08-10-scenarios-semantics-tab.md`). What a selection leaves behind
/// is a lit row and a detail pane, never a rectangle on the picture — hover
/// draws, exactly as everywhere else.
class SemanticsView extends StatefulWidget {
  const SemanticsView({
    super.key,
    required this.root,
    required this.placeholder,
    required this.highlight,
  });

  /// The tree, or null when this step has none — the [placeholder] says why.
  final SemanticsSnapshotNode? root;

  final String placeholder;

  /// The hovered node, drawn on the screenshot by the host's overlay.
  final ValueNotifier<SemanticsSnapshotNode?> highlight;

  @override
  State<SemanticsView> createState() => _SemanticsViewState();
}

class _SemanticsViewState extends State<SemanticsView> {
  /// The list's share of the width — the same resting split as
  /// `ElementsView`, because the two panes stack in the same dock.
  double _split = 0.62;

  /// Local, and cleared when the tree is replaced: the selection is an
  /// object in *this* tree, and a fresh read means whatever it pointed at is
  /// gone — holding it would detail a node the list no longer shows.
  SemanticsSnapshotNode? _selected;

  @override
  void didUpdateWidget(SemanticsView old) {
    super.didUpdateWidget(old);
    if (!identical(old.root, widget.root)) _selected = null;
  }

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

    // Flattened with depth, root's chrome included: unlike the widget tree
    // there is no folding — a semantics tree is already the summary, and
    // reading order top to bottom is the point of the listing.
    var rows = <(SemanticsSnapshotNode, int)>[];
    void walk(SemanticsSnapshotNode node, int depth) {
      rows.add((node, depth));
      for (var child in node.children) {
        walk(child, depth + 1);
      }
    }

    walk(root, 0);

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var listWidth = (constraints.maxWidth * _split)
              .clamp(200.0, math.max(200.0, constraints.maxWidth - 220))
              .toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: listWidth,
                child: Container(
                  color: context.colors.panel,
                  child: MouseRegion(
                    onExit: (_) => widget.highlight.value = null,
                    child: ListView.builder(
                      primary: false,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        var (node, depth) = rows[index];
                        return _SemanticsRow(
                          node: node,
                          indent: math.min(depth * 12.0, listWidth * 0.4),
                          highlight: widget.highlight,
                          selected: identical(node, _selected),
                          onTap: () => setState(() => _selected = node),
                        );
                      },
                    ),
                  ),
                ),
              ),
              InspectSplitGrip(
                axis: Axis.vertical,
                onDrag: (delta) => setState(() {
                  _split = ((listWidth + delta) / constraints.maxWidth).clamp(
                    0.2,
                    0.85,
                  );
                }),
              ),
              Expanded(child: _Detail(node: _selected)),
            ],
          );
        },
      ),
    );
  }
}

class _SemanticsRow extends StatelessWidget {
  const _SemanticsRow({
    required this.node,
    required this.indent,
    required this.highlight,
    required this.selected,
    required this.onTap,
  });

  final SemanticsSnapshotNode node;
  final double indent;
  final ValueNotifier<SemanticsSnapshotNode?> highlight;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var hasWords =
        node.label.isNotEmpty ||
        node.value.isNotEmpty ||
        node.tooltip.isNotEmpty;
    return InkWell(
      onTap: onTap,
      onHover: (over) {
        if (over) {
          highlight.value = node;
        } else if (identical(highlight.value, node)) {
          highlight.value = null;
        }
      },
      child: ValueListenableBuilder(
        valueListenable: highlight,
        builder: (context, lit, child) => Container(
          // Selection outranks hover: one is where you are, the other is
          // where you were going.
          color: selected
              ? colors.accentSoft
              : identical(lit, node)
              ? colors.panel2
              : null,
          child: child,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: FwSpacing.md + indent,
            right: FwSpacing.md,
            top: 3,
            bottom: 3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        node.headline,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: context.type.caption.copyWith(
                          // Words bright, structure dim: the listing reads as
                          // the reader would speak it.
                          color: hasWords ? colors.ink : colors.mut2,
                        ),
                      ),
                    ),
                    if (node.role case var role? when hasWords) ...[
                      const SizedBox(width: FwSpacing.sm),
                      _Badge(role),
                    ],
                    if (node.hint.isNotEmpty) ...[
                      const SizedBox(width: FwSpacing.sm),
                      Flexible(
                        child: Text(
                          node.hint,
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
              if (node.actions.isNotEmpty)
                Text(
                  node.actions.join(' · '),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: context.type.micro.copyWith(color: colors.mut3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One node's full reading — what the row elides.
///
/// The row is tuned for scanning: the headline, one badge, the hint if it
/// fits. This is where the rest goes — every flag, every action, the rect —
/// so nothing about a node is only discoverable by making the panel wide.
class _Detail extends StatelessWidget {
  const _Detail({required this.node});

  final SemanticsSnapshotNode? node;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var it = node;
    if (it == null) {
      return Container(
        color: colors.panel2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          'Select a node',
          textAlign: TextAlign.center,
          style: context.type.caption.copyWith(color: colors.mut),
        ),
      );
    }

    return Container(
      color: colors.panel2,
      child: ListView(
        primary: false,
        padding: const EdgeInsets.all(FwSpacing.lg),
        children: [
          SelectableText(
            it.headline,
            style: context.type.bodyStrong.copyWith(color: colors.ink),
          ),
          const SizedBox(height: FwSpacing.md),
          if (it.label.isNotEmpty) _Pair(label: 'label', value: it.label),
          if (it.value.isNotEmpty) _Pair(label: 'value', value: it.value),
          if (it.hint.isNotEmpty) _Pair(label: 'hint', value: it.hint),
          if (it.tooltip.isNotEmpty) _Pair(label: 'tooltip', value: it.tooltip),
          if (it.identifier.isNotEmpty)
            _Pair(label: 'identifier', value: it.identifier),
          if (it.textDirection.isNotEmpty)
            _Pair(label: 'direction', value: it.textDirection),
          if (it.flags.isNotEmpty)
            _Pair(label: 'flags', value: it.flags.join(', ')),
          if (it.actions.isNotEmpty)
            _Pair(label: 'actions', value: it.actions.join(', ')),
          const SizedBox(height: FwSpacing.md),
          _Pair(
            label: 'rect',
            value:
                '${_n(it.rect.left)}, ${_n(it.rect.top)} — '
                '${_n(it.rect.width)} × ${_n(it.rect.height)}',
          ),
        ],
      ),
    );
  }

  /// Whole pixels without the `.0`, matching the elements detail pane.
  static String _n(double value) => value == value.roundToDouble()
      ? '${value.round()}'
      : value.toStringAsFixed(1);
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

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(context.radii.micro),
      ),
      child: Text(
        text,
        style: context.type.micro.copyWith(color: colors.accent),
      ),
    );
  }
}
