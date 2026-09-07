import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../../ui/action_button.dart';
import '../../ui/context_menu.dart';
import '../editor.dart';
import 'drawer_pane.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';
import 'tokens_host.dart';

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
  const SceneParamPane(this.editor, this.name, {super.key, this.tokens});

  final SceneEditor editor;
  final String name;

  /// The group's libraries, for SHARE: the parameter becomes a token of
  /// one of them and every scene of the group may read it.
  final SceneTokensHost? tokens;

  @override
  Widget build(BuildContext context) {
    var p = editor.doc.paramNamed(name);
    if (p == null) return const SizedBox.shrink();
    var readers = editor.readersOf(p.name);
    Widget? share;
    if (tokens case var host? when host.libraries.isNotEmpty) {
      if (p.kind != SceneParamKind.list) {
        share = Builder(
          builder: (context) => FwActionButton(
            label: 'Share',
            tooltip:
                'A token of the group, with this default — '
                'every scene may read it; this parameter goes',
            onPressed: () async {
              var box = context.findRenderObject()! as RenderBox;
              var at = box.localToGlobal(Offset(0, box.size.height));
              await showContextMenu(context, at, [
                const MenuHeader('Share into'),
                for (var library in host.libraries)
                  MenuItem(
                    library.symbol,
                    icon: Icons.ios_share_outlined,
                    onSelected: () => editor.shareParam(
                      p.name,
                      (name, kind, value) => library.add(
                        name,
                        kind,
                        value: value,
                        taken: host.takenIn(editor),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        );
      }
    }
    return DrawerPane(
      key: ValueKey('pane:param:${p.name}'),
      sections: [
        DrawerSection(title: 'Default', child: _control(context, p)),
        readersSection(context, editor, readers, action: share),
      ],
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
