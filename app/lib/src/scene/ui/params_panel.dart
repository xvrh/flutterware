import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../editor.dart';
import '../../ui/tappable.dart';
import 'inline_name.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';

/// The scene's own parameters — its constructor, seen as a panel.
///
/// One row per parameter: the name (double-click to rename), its kind, and
/// the mockup in the kind's own control, editable in place, because the
/// default IS the mockup and every node reading it follows. The row's menu
/// renames, retypes, reorders and deletes; the last two are refused, not
/// hidden, while something still reads the parameter, and say what does.
class SceneParamsPanel extends StatefulWidget {
  const SceneParamsPanel(this.editor, {super.key});

  final SceneEditor editor;

  @override
  State<SceneParamsPanel> createState() => _SceneParamsPanelState();
}

class _SceneParamsPanelState extends State<SceneParamsPanel> {
  SceneEditor get editor => widget.editor;
  SceneDocument get doc => editor.doc;

  /// The parameter whose name is being edited in place, if any.
  String? _renaming;

  static const _kinds = [
    (SceneParamKind.string, 'Text', 'String'),
    (SceneParamKind.number, 'Number', 'double'),
    (SceneParamKind.color, 'Colour', 'SceneColor'),
    (SceneParamKind.bool, 'Toggle', 'bool'),
  ];

  static String _kindLabel(SceneParamKind kind) => switch (kind) {
    SceneParamKind.string => 'text',
    SceneParamKind.number => 'number',
    SceneParamKind.color => 'colour',
    SceneParamKind.bool => 'toggle',
    SceneParamKind.list => 'list',
  };

  @override
  Widget build(BuildContext context) {
    var params = doc.params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Parameters',
                style: context.type.caption.copyWith(
                  color: context.colors.mut2,
                ),
              ),
            ),
            GestureDetector(
              onTapDown: (d) => _addMenu(context, d.globalPosition),
              child: Text(
                'add',
                style: context.type.caption.copyWith(
                  color: context.colors.accent,
                ),
              ),
            ),
          ],
        ),
        if (params.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FwSpacing.xs),
            child: Text(
              'None. A parameter is a hole a caller fills; its default is '
              'what you see here. Right-click a property to make one of it.',
              style: context.type.micro.copyWith(color: context.colors.mut2),
            ),
          ),
        for (var (i, p) in params.indexed) _row(context, i, p),
      ],
    );
  }

  Widget _row(BuildContext context, int index, SceneParamDecl p) {
    var readers = editor.readersOf(p.name);
    return Padding(
      padding: const EdgeInsets.only(top: FwSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onSecondaryTapDown: (d) =>
                _rowMenu(context, d.globalPosition, index, p, readers),
            onDoubleTap: () => setState(() => _renaming = p.name),
            child: Row(
              children: [
                Expanded(
                  child: _renaming == p.name
                      ? InlineNameField(
                          initial: p.name,
                          dense: true,
                          style: context.type.mono,
                          onCommit: (wanted) => _rename(p.name, wanted),
                          onCancel: () => setState(() => _renaming = null),
                        )
                      : Text(
                          p.name,
                          style: context.type.mono,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                Text(
                  readers.isEmpty
                      ? _kindLabel(p.kind)
                      : '${_kindLabel(p.kind)} · read by ${readers.length}',
                  style: context.type.micro.copyWith(
                    color: context.colors.mut2,
                  ),
                ),
                const SizedBox(width: FwSpacing.xs),
                GestureDetector(
                  onTapDown: (d) =>
                      _rowMenu(context, d.globalPosition, index, p, readers),
                  child: Icon(
                    Icons.more_horiz,
                    size: FwIconSize.sm,
                    color: context.colors.mut2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FwSpacing.xs),
          _control(context, p),
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

  String? _rename(String name, String wanted) {
    if (wanted.trim() == name) {
      setState(() => _renaming = null);
      return null;
    }
    try {
      editor.renameParam(name, wanted);
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
    setState(() => _renaming = null);
    return null;
  }

  void _addMenu(BuildContext context, Offset at) {
    showContextMenu(context, at, [
      const MenuHeader('New parameter'),
      for (var (kind, label, type) in _kinds)
        MenuItem(
          label,
          shortcut: type,
          onSelected: () {
            var name = editor.freeParamName(kind.name);
            editor.addParam(name, kind);
            setState(() => _renaming = name);
          },
        ),
    ]);
  }

  void _rowMenu(
    BuildContext context,
    Offset at,
    int index,
    SceneParamDecl p,
    List<(SceneNode, String)> readers,
  ) {
    var readBy = readers.isEmpty
        ? null
        : 'read by ${readers.map((r) => '${r.$1.name}.${r.$2}').join(', ')}';
    showContextMenu(context, at, [
      MenuItem(
        'Rename',
        icon: Icons.edit_outlined,
        shortcut: 'double-click',
        onSelected: () => setState(() => _renaming = p.name),
      ),
      if (p.kind != SceneParamKind.list) ...[
        const MenuDivider(),
        MenuHeader(readBy == null ? 'Type' : 'Type — $readBy'),
        for (var (kind, label, type) in _kinds)
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
        onSelected: index == 0
            ? null
            : () => editor.moveParam(p.name, index - 1),
      ),
      MenuItem(
        'Move down',
        icon: Icons.arrow_downward,
        onSelected: index == doc.params.length - 1
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
    ]);
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
