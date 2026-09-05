import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import 'inline_name.dart';

/// The line above the drawer under the canvas, naming the one thing that is
/// open there — a motion's timeline, a list parameter's table — and nothing
/// else.
///
/// Left, the chevron folds the drawer away without closing it: the header
/// stays as a one-line reminder, the motion stays on the picture. Then the
/// kind, the name with a switcher among its siblings, and the item's own
/// facts. Right, the drawer's actions and the cross that closes it. Nothing
/// open, it says where to go. Never chips: twelve motions are twelve rows in
/// the tree, and one name here.
class SceneDrawerHeader extends StatefulWidget {
  const SceneDrawerHeader(
    this.editor, {
    super.key,
    required this.onClose,
    required this.onPick,
  });

  final SceneEditor editor;

  /// Closes whatever is open — for a motion, the scene as authored.
  final VoidCallback onClose;

  /// Opens a motion (starting its playback) or a list parameter.
  final ValueChanged<SceneAside> onPick;

  @override
  State<SceneDrawerHeader> createState() => _SceneDrawerHeaderState();
}

class _SceneDrawerHeaderState extends State<SceneDrawerHeader> {
  SceneEditor get editor => widget.editor;
  bool _renaming = false;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;
    var open = editor.drawer;
    var active = open?.name;
    var isMotion = open is MotionAside;
    var thing = isMotion ? 'timeline' : 'table';
    var collapsed = editor.drawerCollapsed;
    return Container(
      height: 32,
      color: colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      child: Row(
        spacing: FwSpacing.sm,
        children: [
          Tooltip(
            message: open == null
                ? 'Open a motion to see its timeline'
                : collapsed
                ? 'Show the $thing'
                : 'Fold the $thing away — the '
                      '${isMotion ? 'motion' : 'parameter'} stays open',
            child: Tappable(
              onTap: active == null
                  ? null
                  : () => editor.drawerCollapsed = !collapsed,
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.xs),
                child: Icon(
                  active == null || collapsed
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: FwIconSize.md,
                  color: active == null ? colors.mut3 : colors.ink,
                ),
              ),
            ),
          ),
          if (open == null || active == null)
            Text(
              'Open a motion or a parameter from the tree  ›',
              style: type.caption.copyWith(color: colors.mut2),
            )
          else ...[
            Text(
              isMotion ? 'Motion ·' : 'Parameter ·',
              style: type.caption.copyWith(color: colors.mut2),
            ),
            GestureDetector(
              onDoubleTap: () => setState(() => _renaming = true),
              onSecondaryTapUp: (d) => _menu(context, d.globalPosition, open),
              child: _renaming
                  ? SizedBox(
                      width: 160,
                      child: InlineNameField(
                        initial: active,
                        dense: true,
                        style: type.bodyStrong,
                        onCommit: (wanted) => _rename(open, wanted),
                        onCancel: () => setState(() => _renaming = false),
                      ),
                    )
                  : Text(active, style: type.bodyStrong),
            ),
            if (_openable().length > 1)
              Tooltip(
                message: 'Switch to another motion or parameter',
                child: GestureDetector(
                  onTapDown: (d) => _switcher(context, d.globalPosition),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: FwIconSize.md,
                    color: colors.mut,
                  ),
                ),
              ),
            const SizedBox(width: FwSpacing.sm),
            Text(
              _facts(open),
              style: type.caption.copyWith(color: colors.mut2),
            ),
            const Spacer(),
            if (open is ParamAside)
              Tappable(
                onTap: () => _addRow(open.name),
                child: Text(
                  'add row',
                  style: type.caption.copyWith(color: colors.accent),
                ),
              ),
            Tooltip(
              message: isMotion
                  ? 'Close the motion — the scene as authored'
                  : 'Close the table',
              child: Tappable(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
                child: Padding(
                  padding: const EdgeInsets.all(FwSpacing.xs),
                  child: Icon(
                    Icons.close,
                    size: FwIconSize.sm,
                    color: colors.mut,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _facts(SceneAside open) {
    switch (open) {
      case MotionAside(:var name):
        var m = editor.motions[name]!;
        var seconds = m.durationOf(m.timeline).inMilliseconds / 1000;
        var groups = m.groups.length;
        return '${seconds.toStringAsFixed(2)}s · '
            '$groups ${groups == 1 ? 'group' : 'groups'}';
      case ParamAside(:var name):
        var p = editor.doc.paramNamed(name)!;
        var readers = editor.readersOf(name).length;
        return '${p.items.length} ${p.items.length == 1 ? 'item' : 'items'}'
            ' · read by $readers';
    }
  }

  void _addRow(String name) {
    var items = editor.doc.paramNamed(name)!.items;
    if (items.isEmpty) return;
    editor.setParamDefault(name, [
      ...items,
      {...items.last},
    ]);
  }

  String? _rename(SceneAside open, String wanted) {
    try {
      switch (open) {
        case MotionAside(:var name):
          editor.renameMotion(name, wanted);
        case ParamAside(:var name):
          editor.renameParam(name, wanted);
      }
    } on ArgumentError catch (e) {
      return e.message as String?;
    }
    setState(() => _renaming = false);
    return null;
  }

  void _menu(BuildContext context, Offset at, SceneAside open) {
    var name = open.name;
    showContextMenu(context, at, [
      MenuItem(
        'Rename $name…',
        icon: Icons.edit_outlined,
        shortcut: 'double-click',
        onSelected: () => setState(() => _renaming = true),
      ),
      if (open is MotionAside)
        MenuItem(
          'Delete $name',
          icon: Icons.close,
          danger: true,
          onSelected: () => editor.removeMotion(name),
        ),
    ]);
  }

  /// Everything that can be open here: the motions, then the list
  /// parameters.
  List<SceneAside> _openable() => [
    for (var name in editor.motions.keys) MotionAside(name),
    for (var p in editor.doc.params)
      if (p.kind == SceneParamKind.list) ParamAside(p.name),
  ];

  void _switcher(BuildContext context, Offset at) {
    var open = editor.drawer;
    var all = _openable();
    var motions = all.whereType<MotionAside>().toList();
    var params = all.whereType<ParamAside>().toList();
    showContextMenu(context, at, [
      if (motions.isNotEmpty) const MenuHeader('Motions'),
      for (var m in motions)
        MenuItem(
          m.name,
          icon: m == open ? Icons.check : null,
          onSelected: m == open ? null : () => widget.onPick(m),
        ),
      if (params.isNotEmpty) const MenuHeader('Parameters'),
      for (var p in params)
        MenuItem(
          p.name,
          icon: p == open ? Icons.check : null,
          onSelected: p == open ? null : () => widget.onPick(p),
        ),
    ]);
  }
}
