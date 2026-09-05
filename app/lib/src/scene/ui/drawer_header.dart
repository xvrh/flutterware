import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import 'inline_name.dart';

/// The line above the drawer under the canvas, naming the one thing that is
/// open there — a motion's timeline — and nothing else.
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

  /// Closes the open motion — the scene as authored.
  final VoidCallback onClose;

  /// Opens a motion, starting its playback.
  final ValueChanged<String> onPick;

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
    var active = editor.activeMotion;
    var collapsed = editor.drawerCollapsed;
    return Container(
      height: 32,
      color: colors.panel,
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      child: Row(
        spacing: FwSpacing.sm,
        children: [
          Tooltip(
            message: active == null
                ? 'Open a motion to see its timeline'
                : collapsed
                ? 'Show the timeline'
                : 'Fold the timeline away — the motion stays open',
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
          if (active == null)
            Text(
              'Open a motion or a parameter from the tree  ›',
              style: type.caption.copyWith(color: colors.mut2),
            )
          else ...[
            Text('Motion ·', style: type.caption.copyWith(color: colors.mut2)),
            GestureDetector(
              onDoubleTap: () => setState(() => _renaming = true),
              onSecondaryTapUp: (d) => _menu(context, d.globalPosition, active),
              child: _renaming
                  ? SizedBox(
                      width: 160,
                      child: InlineNameField(
                        initial: active,
                        dense: true,
                        style: type.bodyStrong,
                        onCommit: (wanted) => _rename(active, wanted),
                        onCancel: () => setState(() => _renaming = false),
                      ),
                    )
                  : Text(active, style: type.bodyStrong),
            ),
            if (editor.motions.length > 1)
              Tooltip(
                message: 'Switch to another motion',
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
              _facts(active),
              style: type.caption.copyWith(color: colors.mut2),
            ),
            const Spacer(),
            Tooltip(
              message: 'Close the motion — the scene as authored',
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

  String _facts(String name) {
    var m = editor.motions[name]!;
    var seconds = m.durationOf(m.timeline).inMilliseconds / 1000;
    var groups = m.groups.length;
    return '${seconds.toStringAsFixed(2)}s · $groups ${groups == 1 ? 'group' : 'groups'}';
  }

  String? _rename(String name, String wanted) {
    try {
      editor.renameMotion(name, wanted);
    } on ArgumentError catch (e) {
      return e.message as String?;
    }
    setState(() => _renaming = false);
    return null;
  }

  void _menu(BuildContext context, Offset at, String name) {
    showContextMenu(context, at, [
      MenuItem(
        'Rename $name…',
        icon: Icons.edit_outlined,
        shortcut: 'double-click',
        onSelected: () => setState(() => _renaming = true),
      ),
      MenuItem(
        'Delete $name',
        icon: Icons.close,
        danger: true,
        onSelected: () => editor.removeMotion(name),
      ),
    ]);
  }

  void _switcher(BuildContext context, Offset at) {
    var active = editor.activeMotion;
    showContextMenu(context, at, [
      const MenuHeader('Motions'),
      for (var name in editor.motions.keys)
        MenuItem(
          name,
          icon: name == active ? Icons.check : null,
          onSelected: name == active ? null : () => widget.onPick(name),
        ),
    ]);
  }
}
