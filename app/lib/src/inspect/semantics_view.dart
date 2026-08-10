import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'semantics_node.dart';

/// The Semantics tab: what a screen reader gets, in reading order, each row
/// lighting its rect up on the picture — a scenario step's screenshot, or
/// the catalog's live preview; the view neither knows nor cares which.
/// Deliberately hover-only — no selection, no address — until the picker
/// learns to answer from two trees (see
/// `2026-08-10-scenarios-semantics-tab.md`).
class SemanticsView extends StatelessWidget {
  const SemanticsView({
    super.key,
    required this.root,
    required this.placeholder,
    required this.highlight,
  });

  /// The tree, or null when this step has none — the [placeholder] says why.
  final SemanticsSnapshotNode? root;

  final String placeholder;

  /// The hovered node, drawn on the screenshot by the step page's overlay.
  final ValueNotifier<SemanticsSnapshotNode?> highlight;

  @override
  Widget build(BuildContext context) {
    var root = this.root;
    if (root == null) {
      return Container(
        color: context.colors.panel,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Text(
          placeholder,
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

    return Container(
      color: context.colors.panel,
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) => MouseRegion(
            onExit: (_) => highlight.value = null,
            child: ListView.builder(
              primary: false,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                var (node, depth) = rows[index];
                return _SemanticsRow(
                  node: node,
                  indent: math.min(depth * 12.0, constraints.maxWidth * 0.4),
                  highlight: highlight,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SemanticsRow extends StatelessWidget {
  const _SemanticsRow({
    required this.node,
    required this.indent,
    required this.highlight,
  });

  final SemanticsSnapshotNode node;
  final double indent;
  final ValueNotifier<SemanticsSnapshotNode?> highlight;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var hasWords =
        node.label.isNotEmpty ||
        node.value.isNotEmpty ||
        node.tooltip.isNotEmpty;
    return InkWell(
      onTap: null,
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
          color: identical(lit, node) ? colors.panel2 : null,
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
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: context.type.micro.copyWith(color: colors.accent),
      ),
    );
  }
}
