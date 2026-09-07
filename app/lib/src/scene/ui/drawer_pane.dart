import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/tappable.dart';
import '../editor.dart';

/// The shape every pane in the drawer under the canvas takes: a band of
/// titled columns, side by side, each scrolling on its own.
///
/// The drawer is wide and short — a third of the window's height at most,
/// all of its width — so a pane lays its parts out ACROSS it, never down
/// it. A token's modes are columns (the way a design tool's variables
/// table has one column per mode), a library's modes and tokens and
/// design file are columns, a parameter's default and its readers are
/// columns. A column outgrowing the band scrolls; more columns than fit
/// scroll sideways. Nothing here can overflow.
class DrawerPane extends StatelessWidget {
  const DrawerPane({super.key, required this.sections});

  final List<DrawerSection> sections;

  /// The least a flexible column gets before the band scrolls sideways.
  static const minFlexWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      color: colors.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var fixed = 0.0;
          var flexible = 0;
          for (var s in sections) {
            if (s.width case var w?) {
              fixed += w;
            } else {
              flexible++;
            }
          }
          var dividers = math.max(0, sections.length - 1) * 1.0;
          var available = constraints.maxWidth - dividers;
          var flexWidth = flexible == 0
              ? 0.0
              : math.max(minFlexWidth, (available - fixed) / flexible);
          var total = fixed + flexible * flexWidth + dividers;
          var row = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var (i, s) in sections.indexed) ...[
                if (i > 0) Container(width: 1, color: colors.line),
                SizedBox(
                  key: s.key,
                  width: s.width ?? flexWidth,
                  child: _Section(s),
                ),
              ],
            ],
          );
          if (total <= constraints.maxWidth + 0.5) return row;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: total, child: row),
          );
        },
      ),
    );
  }
}

/// One column of a [DrawerPane]: a caption, something at its right end,
/// and a body that scrolls when the band is shorter than it.
class DrawerSection {
  const DrawerSection({
    required this.title,
    required this.child,
    this.width,
    this.trailing,
    this.key,
  });

  final String title;
  final Widget child;

  /// Fixed, or null for a share of what is left.
  final double? width;

  /// A link or a word beside the title — `unset`, `same as default`.
  final Widget? trailing;

  final Key? key;
}

class _Section extends StatelessWidget {
  const _Section(this.section);

  final DrawerSection section;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FwSpacing.lg,
            FwSpacing.md,
            FwSpacing.lg,
            FwSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  section.title,
                  overflow: TextOverflow.ellipsis,
                  style: caption,
                ),
              ),
              if (section.trailing case var trailing?)
                Flexible(child: trailing),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              FwSpacing.lg,
              0,
              FwSpacing.lg,
              FwSpacing.md,
            ),
            child: section.child,
          ),
        ),
      ],
    );
  }
}

/// A small link in a section's title row — `unset`, `same as default`.
class DrawerLink extends StatelessWidget {
  const DrawerLink(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var style = context.type.caption.copyWith(
      color: onTap == null ? colors.mut3 : colors.accent,
    );
    var text = Text(label, overflow: TextOverflow.ellipsis, style: style);
    if (onTap == null) return text;
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FwSpacing.xxs),
        child: text,
      ),
    );
  }
}

/// A chip that names a node and a property, and steps to the node.
class ReaderChip extends StatelessWidget {
  const ReaderChip(this.label, {super.key, this.onTap, this.muted = false});

  final String label;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var text = Text(
      label,
      style: context.type.mono.copyWith(
        color: muted ? colors.mut : colors.accentDark,
      ),
    );
    if (onTap == null) return text;
    return Tappable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.xs,
          vertical: FwSpacing.xxs,
        ),
        child: text,
      ),
    );
  }
}

/// The column every value pane ends with: who reads the thing, each a
/// step to the node; readers in other scenes of the group, named; and the
/// one move the thing offers — Share, Make local.
DrawerSection readersSection(
  BuildContext context,
  SceneEditor editor,
  List<(SceneNode, String)> readers, {
  List<String> elsewhere = const [],
  Widget? action,
}) {
  var colors = context.colors;
  var caption = context.type.caption.copyWith(color: colors.mut2);
  return DrawerSection(
    title: readers.isEmpty ? 'Read by nothing here' : 'Read by',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (readers.isEmpty)
          Text(
            'Right-click a property of a node to bind it here.',
            style: context.type.micro.copyWith(color: colors.mut2),
          ),
        Wrap(
          spacing: FwSpacing.md,
          runSpacing: FwSpacing.xxs,
          children: [
            for (var (node, prop) in readers)
              ReaderChip(
                '${node.name} · $prop',
                onTap: () => editor.select(node),
              ),
          ],
        ),
        if (elsewhere.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: FwSpacing.md,
              bottom: FwSpacing.xs,
            ),
            child: Text('Elsewhere in the group', style: caption),
          ),
          Wrap(
            spacing: FwSpacing.md,
            runSpacing: FwSpacing.xxs,
            children: [for (var r in elsewhere) ReaderChip(r, muted: true)],
          ),
        ],
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: FwSpacing.lg),
            // A row, so the button takes its own width, not the column's.
            child: Row(mainAxisSize: MainAxisSize.min, children: [action]),
          ),
      ],
    ),
  );
}
