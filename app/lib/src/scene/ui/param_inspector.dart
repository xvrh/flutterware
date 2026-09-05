import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import 'inline_name.dart';
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

/// The menu a parameter row offers, wherever the row is: rename, retype,
/// reorder, delete. Retype and delete are refused, not hidden, while
/// something reads the parameter, and say what does.
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

/// The inspector for one parameter, selected in the tree's outline: what it
/// is, the mockup in the kind's own control — editable, because the default
/// IS the mockup and every node reading it follows — and what reads it,
/// each a step to that node.
class SceneParamInspector extends StatefulWidget {
  const SceneParamInspector(this.editor, this.name, {super.key});

  final SceneEditor editor;
  final String name;

  @override
  State<SceneParamInspector> createState() => _SceneParamInspectorState();
}

class _SceneParamInspectorState extends State<SceneParamInspector> {
  SceneEditor get editor => widget.editor;
  bool _renaming = false;

  @override
  Widget build(BuildContext context) {
    var p = editor.doc.paramNamed(widget.name);
    if (p == null) return const SizedBox.shrink();
    var readers = editor.readersOf(p.name);
    var caption = context.type.caption.copyWith(color: context.colors.mut2);
    return ListView(
      key: ValueKey('inspector:param:${p.name}'),
      padding: const EdgeInsets.all(FwSpacing.lg),
      children: [
        GestureDetector(
          onDoubleTap: () => setState(() => _renaming = true),
          onSecondaryTapDown: (d) => showContextMenu(
            context,
            d.globalPosition,
            paramMenu(
              editor,
              p,
              onRename: () => setState(() => _renaming = true),
            ),
          ),
          child: Row(
            children: [
              Text('Parameter · ', style: context.type.bodyStrong),
              Expanded(
                child: _renaming
                    ? InlineNameField(
                        initial: p.name,
                        dense: true,
                        style: context.type.bodyStrong,
                        onCommit: _rename,
                        onCancel: () => setState(() => _renaming = false),
                      )
                    : Text(
                        p.name,
                        style: context.type.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              GestureDetector(
                onTapDown: (d) => showContextMenu(
                  context,
                  d.globalPosition,
                  paramMenu(
                    editor,
                    p,
                    onRename: () => setState(() => _renaming = true),
                  ),
                ),
                child: Icon(
                  Icons.more_horiz,
                  size: FwIconSize.sm,
                  color: context.colors.mut2,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xxs),
          child: Text(
            '${paramKindLabel(p.kind)} · ${p.typeName}',
            style: caption,
          ),
        ),
        const SizedBox(height: FwSpacing.lg),
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Text(
            p.kind == SceneParamKind.list ? 'Items' : 'Default',
            style: caption,
          ),
        ),
        _control(context, p),
        const SizedBox(height: FwSpacing.lg),
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
            style: context.type.micro.copyWith(color: context.colors.mut2),
          ),
        for (var (node, prop) in readers)
          Tappable(
            onTap: () => editor.select(node),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
              child: Text(
                '${node.name} · $prop',
                style: context.type.mono.copyWith(
                  color: context.colors.accentDark,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String? _rename(String wanted) {
    try {
      editor.renameParam(widget.name, wanted);
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
    setState(() => _renaming = false);
    return null;
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
        return _ListEditor(editor, p);
    }
  }
}

/// The inspector for one motion, selected in the outline: its length, and
/// the groups it is made of, each a step to the node it animates. Opening
/// the timeline is the drawer's business, offered here as well.
class SceneMotionInspector extends StatelessWidget {
  const SceneMotionInspector(this.editor, this.name, {super.key, this.onOpen});

  final SceneEditor editor;
  final String name;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    var m = editor.motions[name];
    if (m == null) return const SizedBox.shrink();
    var caption = context.type.caption.copyWith(color: context.colors.mut2);
    var duration = m.durationOf(m.timeline);
    return ListView(
      key: ValueKey('inspector:motion:$name'),
      padding: const EdgeInsets.all(FwSpacing.lg),
      children: [
        Text('Motion · $name', style: context.type.bodyStrong),
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xxs),
          child: Text(
            '${(duration.inMilliseconds / 1000).toStringAsFixed(2)}s · '
            '${m.groups.length} ${m.groups.length == 1 ? 'group' : 'groups'}'
            ' · on ${m.sceneClassName}',
            style: caption,
          ),
        ),
        const SizedBox(height: FwSpacing.lg),
        if (onOpen case var open?)
          Tappable(
            onTap: () => open(name),
            child: Text(
              editor.activeMotion == name
                  ? 'Timeline is open below'
                  : 'Open the timeline',
              style: context.type.caption.copyWith(
                color: editor.activeMotion == name
                    ? context.colors.mut2
                    : context.colors.accent,
              ),
            ),
          ),
        const SizedBox(height: FwSpacing.lg),
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.xs),
          child: Text(
            m.groups.isEmpty ? 'No groups yet' : 'Groups',
            style: caption,
          ),
        ),
        for (var g in m.groups)
          Tappable(
            onTap: () => editor.select(g.node),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FwSpacing.xxs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      g.name,
                      style: context.type.mono,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${g.node.name} · ${g.tracks.length + g.args.length} '
                    '${g.tracks.length + g.args.length == 1 ? 'track' : 'tracks'}',
                    style: context.type.micro.copyWith(
                      color: context.colors.mut2,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A list parameter's mockup as a small table: one column per field, one
/// row per item, each cell in its own control. Rows are added (a copy of
/// the last, so the shape is kept) and removed here; the FIELDS are the
/// record type every row shares and every cell binding names, so they are
/// still edited in the file. Every change is one door on the parameter, and
/// the repeat that draws the list redraws.
class _ListEditor extends StatelessWidget {
  const _ListEditor(this.editor, this.param);

  final SceneEditor editor;
  final SceneParamDecl param;

  List<SceneItem> get items => param.items;

  void _set(List<SceneItem> next, {String? mergeKey}) =>
      editor.setParamDefault(param.name, next, mergeKey: mergeKey);

  void _cell(int row, String field, Object value, {String? mergeKey}) => _set([
    for (var (i, item) in items.indexed)
      i == row ? {...item, field: value} : item,
  ], mergeKey: mergeKey);

  @override
  Widget build(BuildContext context) {
    var fields = items.isEmpty ? const <String>[] : items.first.keys.toList();
    var caption = context.type.micro.copyWith(color: context.colors.mut2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          Text('no items — the repeat draws nothing', style: caption)
        else ...[
          Row(
            children: [
              for (var f in fields) Expanded(child: Text(f, style: caption)),
              const SizedBox(width: FwIconSize.sm + FwSpacing.xs),
            ],
          ),
          for (var (i, item) in items.indexed)
            Padding(
              padding: const EdgeInsets.only(top: FwSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var (j, f) in fields.indexed) ...[
                    if (j > 0) const SizedBox(width: FwSpacing.xs),
                    Expanded(child: _cellControl(context, i, f, item[f])),
                  ],
                  const SizedBox(width: FwSpacing.xs),
                  Tappable(
                    onTap: () => _set([
                      for (var (k, it) in items.indexed)
                        if (k != i) it,
                    ]),
                    child: Icon(
                      Icons.close,
                      size: FwIconSize.sm,
                      color: context.colors.mut2,
                    ),
                  ),
                ],
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: FwSpacing.xs),
          child: Tappable(
            onTap: items.isEmpty
                ? null
                : () => _set([
                    ...items,
                    {...items.last},
                  ]),
            child: Text(
              items.isEmpty ? 'add a first item in the file' : 'add row',
              style: context.type.caption.copyWith(
                color: items.isEmpty
                    ? context.colors.mut2
                    : context.colors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cellControl(BuildContext context, int row, String field, Object? v) {
    var key = 'param:${param.name}:$row:$field';
    return switch (v) {
      double d => SceneNumberField(
        value: d,
        shape: const SceneNumberShape(perPixel: 1, decimals: 2),
        onChanged: (n) => _cell(row, field, n, mergeKey: key),
        onCommit: (n) {
          _cell(row, field, n, mergeKey: key);
          editor.endMerge();
        },
      ),
      _ => TextFormField(
        key: ValueKey(key),
        initialValue: '$v',
        onChanged: (t) => _cell(row, field, t, mergeKey: key),
      ),
    };
  }
}
