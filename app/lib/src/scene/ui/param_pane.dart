import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';

/// The parameter kinds a person can declare, with the word the UI uses and
/// the type the file spells. A list is declared in the file, not here: its
/// shape is a record type nobody should have to type into a menu.
const paramKinds = [
  (SceneParamKind.string, 'Text', 'String'),
  (SceneParamKind.number, 'Number', 'double'),
  (SceneParamKind.color, 'Colour', 'SceneColor'),
  (SceneParamKind.bool, 'Toggle', 'bool'),
];

String paramKindLabel(SceneParamKind kind) => switch (kind) {
  SceneParamKind.string => 'text',
  SceneParamKind.number => 'number',
  SceneParamKind.color => 'colour',
  SceneParamKind.bool => 'toggle',
  SceneParamKind.list => 'list',
};

IconData paramKindIcon(SceneParamKind kind) => switch (kind) {
  SceneParamKind.string => Icons.text_fields,
  SceneParamKind.number => Icons.numbers,
  SceneParamKind.color => Icons.palette_outlined,
  SceneParamKind.bool => Icons.toggle_on_outlined,
  SceneParamKind.list => Icons.table_rows_outlined,
};

/// The menu a parameter offers, wherever it is asked for — its row in the
/// tree, the drawer's header: rename, retype, reorder, delete. Retype and
/// delete are refused, not hidden, while something reads the parameter, and
/// say what does.
List<MenuEntry> paramMenu(
  SceneEditor editor,
  SceneParamDecl p, {
  required VoidCallback onRename,
}) {
  var index = editor.doc.params.indexOf(p);
  var readers = editor.readersOf(p.name);
  var readBy = readers.isEmpty
      ? null
      : 'read by ${readers.map((r) => '${r.$1.name}.${r.$2}').join(', ')}';
  return [
    MenuItem(
      'Rename',
      icon: Icons.edit_outlined,
      shortcut: 'double-click',
      onSelected: onRename,
    ),
    if (p.kind != SceneParamKind.list) ...[
      const MenuDivider(),
      MenuHeader(readBy == null ? 'Type' : 'Type — $readBy'),
      for (var (kind, label, type) in paramKinds)
        MenuItem(
          label,
          icon: kind == p.kind ? Icons.check : null,
          shortcut: type,
          onSelected: readBy != null || kind == p.kind
              ? null
              : () => editor.retypeParam(p.name, kind),
        ),
    ],
    const MenuDivider(),
    MenuItem(
      'Move up',
      icon: Icons.arrow_upward,
      onSelected: index <= 0 ? null : () => editor.moveParam(p.name, index - 1),
    ),
    MenuItem(
      'Move down',
      icon: Icons.arrow_downward,
      onSelected: index < 0 || index == editor.doc.params.length - 1
          ? null
          : () => editor.moveParam(p.name, index + 1),
    ),
    const MenuDivider(),
    MenuItem(
      readBy == null ? 'Delete' : 'Delete — $readBy',
      icon: Icons.delete_outline,
      danger: true,
      onSelected: readBy != null ? null : () => editor.deleteParam(p.name),
    ),
  ];
}

/// One parameter, open in the drawer under the canvas — the same place a
/// motion's timeline opens, because both are things you work on while
/// clicking nodes above: the mockup in the kind's own control, editable
/// because the default IS the mockup and every node reading it follows; and
/// what reads it, each a step to that node. A list opens as its table
/// instead; this is every other kind.
class SceneParamPane extends StatelessWidget {
  const SceneParamPane(this.editor, this.name, {super.key});

  final SceneEditor editor;
  final String name;

  @override
  Widget build(BuildContext context) {
    var p = editor.doc.paramNamed(name);
    if (p == null) return const SizedBox.shrink();
    var readers = editor.readersOf(p.name);
    var colors = context.colors;
    var caption = context.type.caption.copyWith(color: colors.mut2);
    return Container(
      key: ValueKey('pane:param:${p.name}'),
      color: colors.panel,
      padding: const EdgeInsets.all(FwSpacing.lg),
      alignment: Alignment.topLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: FwSpacing.xxl,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: FwSpacing.xs),
                  child: Text('Default', style: caption),
                ),
                _control(context, p),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: FwSpacing.xs),
                  child: Text(
                    readers.isEmpty ? 'Read by nothing yet' : 'Read by',
                    style: caption,
                  ),
                ),
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
                      Tappable(
                        onTap: () => editor.select(node),
                        borderRadius: BorderRadius.circular(
                          context.radii.radiusSmall,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FwSpacing.xs,
                            vertical: FwSpacing.xxs,
                          ),
                          child: Text(
                            '${node.name} · $prop',
                            style: context.type.mono.copyWith(
                              color: colors.accentDark,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The mockup, in the kind's own control.
  Widget _control(BuildContext context, SceneParamDecl p) {
    var key = 'param:${p.name}';
    switch (p.kind) {
      case SceneParamKind.number:
        return SceneNumberField(
          value: p.defaultValue as double,
          shape: const SceneNumberShape(perPixel: 1, decimals: 2),
          onChanged: (v) => editor.setParamDefault(p.name, v, mergeKey: key),
          onCommit: (v) {
            editor.setParamDefault(p.name, v, mergeKey: key);
            editor.endMerge();
          },
        );
      case SceneParamKind.string:
        return TextFormField(
          key: ValueKey(key),
          initialValue: p.defaultValue as String,
          maxLines: 3,
          minLines: 1,
          onChanged: (v) => editor.setParamDefault(p.name, v, mergeKey: key),
        );
      case SceneParamKind.color:
        return SceneSwatches(
          current: p.defaultValue as SceneColor,
          allowNone: false,
          onPick: (c) => editor.setParamDefault(p.name, c!),
        );
      case SceneParamKind.bool:
        var on = p.defaultValue as bool;
        return Tappable(
          onTap: () => editor.setParamDefault(p.name, !on),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.check_box : Icons.check_box_outline_blank,
                size: FwIconSize.md,
                color: on ? context.colors.accent : context.colors.mut2,
              ),
              const SizedBox(width: FwSpacing.sm),
              Text(on ? 'on' : 'off', style: context.type.body),
            ],
          ),
        );
      case SceneParamKind.list:
        // The table's, not this pane's.
        return const SizedBox.shrink();
    }
  }
}
