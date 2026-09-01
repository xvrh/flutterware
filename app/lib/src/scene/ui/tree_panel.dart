import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/split_button.dart';
import '../../ui/tappable.dart';
import '../../ui/tree_row.dart';
import '../editor.dart';
import 'modifiers.dart';

/// The scene's nodes as a tree: one row per node, folded per frame, selected
/// as a set. Hovering a row hovers the node on the canvas and the other way
/// round, because both are the same `SceneEditor.hover`.
class SceneTreePanel extends StatefulWidget {
  const SceneTreePanel(this.editor, {super.key, this.toolbar = true});

  final SceneEditor editor;

  /// Whether to show the add/delete strip above the rows. Off where the
  /// arrangement puts those verbs somewhere else.
  final bool toolbar;

  @override
  State<SceneTreePanel> createState() => _SceneTreePanelState();
}

class _SceneTreePanelState extends State<SceneTreePanel> {
  final _folded = <String>{};

  SceneEditor get editor => widget.editor;
  SceneDocument get doc => editor.doc;

  Iterable<(SceneNode, int)> _rows() sync* {
    Iterable<(SceneNode, int)> visit(SceneNode node, int depth) sync* {
      yield (node, depth);
      if (_folded.contains(node.name)) return;
      for (var child in node.children) {
        yield* visit(child, depth + 1);
      }
    }

    yield* visit(doc.root, 0);
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return AnimatedBuilder(
      animation: Listenable.merge([doc.listenable, editor.listenable]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.toolbar) _Toolbar(editor),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: FwSpacing.xs),
              children: [
                for (var (node, depth) in _rows())
                  MouseRegion(
                    onEnter: (_) => editor.hover = node.name,
                    onExit: (_) {
                      if (editor.hover == node.name) editor.hover = null;
                    },
                    child: FwTreeRow(
                      depth: depth,
                      density: TreeRowDensity.dense,
                      selected: editor.isSelected(node),
                      open: node is FrameNode && node.children.isNotEmpty
                          ? !_folded.contains(node.name)
                          : null,
                      onToggleFold: () => setState(() {
                        if (!_folded.remove(node.name)) _folded.add(node.name);
                      }),
                      leading: Icon(
                        _iconFor(node),
                        size: FwIconSize.sm,
                        color: editor.isSelected(node)
                            ? colors.accentDark
                            : colors.mut,
                      ),
                      label: Text(
                        node.name,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.body.copyWith(
                          color: editor.hover == node.name
                              ? colors.accentDark
                              : colors.ink,
                        ),
                      ),
                      trailing: [
                        if (node is ExternalNode)
                          Text(
                            node.entry,
                            style: context.type.caption.copyWith(
                              color: colors.mut2,
                            ),
                          ),
                      ],
                      onTap: () => editor.select(
                        node == doc.root ? null : node,
                        toggle: toggleModifier,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(SceneNode node) => switch (node) {
    FrameNode() => Icons.crop_square,
    TextNode() => Icons.text_fields,
    ShapeNode() => Icons.circle_outlined,
    ExternalNode() => Icons.extension_outlined,
  };
}

class _Toolbar extends StatelessWidget {
  const _Toolbar(this.editor);

  final SceneEditor editor;

  SceneDocument get doc => editor.doc;

  void _addText() => _add(TextNode(doc.uniqueName('text'), 'Text'));

  void _add(SceneNode node) {
    var target = switch (editor.primary) {
      FrameNode f => f,
      SceneNode n => doc.parentOf(n) ?? doc.root,
      null => doc.root,
    };
    editor.perform('Add ${node.name}', () => target.children.add(node));
    editor.select(node);
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        spacing: FwSpacing.xs,
        children: [
          FwSplitButton(
            label: 'Add',
            icon: Icons.add,
            tooltip: 'Add a text under the selection',
            onPressed: _addText,
            menuTooltip: 'Add something else',
            entries: [
              MenuItem('Text', icon: Icons.text_fields, onSelected: _addText),
              MenuItem(
                'Shape',
                icon: Icons.circle_outlined,
                onSelected: () => _add(
                  ShapeNode(doc.uniqueName('shape'))
                    ..width = 80
                    ..height = 80
                    ..fill = const SceneColor(0xFF888888),
                ),
              ),
              MenuItem(
                'Frame',
                icon: Icons.crop_square,
                onSelected: () => _add(
                  FrameNode(doc.uniqueName('frame'))
                    ..width = 200
                    ..height = 120,
                ),
              ),
            ],
          ),
          const Spacer(),
          Tooltip(
            message: 'Delete the selection',
            child: Tappable(
              onTap: editor.selectedNodes.isEmpty
                  ? null
                  : editor.deleteSelection,
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.xs),
                child: Icon(
                  Icons.delete_outline,
                  size: FwIconSize.md,
                  color: editor.selectedNodes.isEmpty
                      ? colors.mut3
                      : colors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
