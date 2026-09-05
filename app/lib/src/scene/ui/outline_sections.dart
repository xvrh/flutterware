import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../../ui/tree_row.dart';
import '../editor.dart';
import 'inline_name.dart';
import 'param_inspector.dart';

/// The rest of what the file declares, under the layers: its parameters and
/// its motions, each a section with a count and its own `+`.
///
/// A row is SELECTED with a click — the inspector describes it — and the
/// heavy ones are OPENED with their `›` or a double-click: a motion's
/// timeline, a list's table, below the canvas. The distinction is what
/// lets a timeline stay put while nodes are clicked on the canvas to key
/// them. Rename in place with a double-click on the name; right-click for
/// the rest.
class SceneOutlineSections extends StatefulWidget {
  const SceneOutlineSections(
    this.editor, {
    super.key,
    this.sceneClassName,
    this.onOpenMotion,
  });

  final SceneEditor editor;

  /// What a new motion animates; null hides the motions' `+`.
  final String? sceneClassName;

  /// Opens a motion's timeline — the workspace's door, which also starts
  /// its playback.
  final ValueChanged<String>? onOpenMotion;

  @override
  State<SceneOutlineSections> createState() => _SceneOutlineSectionsState();
}

class _SceneOutlineSectionsState extends State<SceneOutlineSections> {
  SceneEditor get editor => widget.editor;
  SceneDocument get doc => editor.doc;

  var _paramsOpen = true;
  var _motionsOpen = true;

  /// The row being renamed in place, if any.
  SceneAside? _renaming;

  @override
  Widget build(BuildContext context) {
    var params = doc.params;
    var motions = editor.motions.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _section(
          context,
          'Parameters',
          params.length,
          open: _paramsOpen,
          onToggle: () => setState(() => _paramsOpen = !_paramsOpen),
          onAdd: (at) => _addParamMenu(context, at),
        ),
        if (_paramsOpen)
          for (var p in params) _paramRow(context, p),
        _section(
          context,
          'Motions',
          motions.length,
          open: _motionsOpen,
          onToggle: () => setState(() => _motionsOpen = !_motionsOpen),
          onAdd: widget.sceneClassName == null
              ? null
              : (_) => _open(editor.addMotion(widget.sceneClassName!)),
        ),
        if (_motionsOpen)
          for (var name in motions) _motionRow(context, name),
        const SizedBox(height: FwSpacing.sm),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String label,
    int count, {
    required bool open,
    required VoidCallback onToggle,
    required void Function(Offset at)? onAdd,
  }) {
    var colors = context.colors;
    var type = context.type;
    return Padding(
      padding: const EdgeInsets.only(
        left: FwSpacing.md,
        right: FwSpacing.sm,
        top: FwSpacing.md,
        bottom: FwSpacing.xs,
      ),
      child: Row(
        children: [
          Tappable(
            onTap: onToggle,
            child: Row(
              children: [
                Icon(
                  open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: FwIconSize.sm,
                  color: colors.mut,
                ),
                const SizedBox(width: FwSpacing.xs),
                Text(label, style: type.sectionLabel),
                const SizedBox(width: FwSpacing.sm),
                Text(
                  '$count',
                  style: type.caption.copyWith(color: colors.mut2),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (onAdd != null)
            Tooltip(
              message:
                  'New ${label.toLowerCase().substring(0, label.length - 1)}',
              child: GestureDetector(
                onTapDown: (d) => onAdd(d.globalPosition),
                child: Padding(
                  padding: const EdgeInsets.all(FwSpacing.xxs),
                  child: Icon(
                    Icons.add,
                    size: FwIconSize.sm,
                    color: colors.mut,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paramRow(BuildContext context, SceneParamDecl p) {
    var aside = ParamAside(p.name);
    var readers = editor.readersOf(p.name).length;
    return _row(
      context,
      aside,
      icon: paramKindIcon(p.kind),
      name: p.name,
      trailing: readers == 0 ? '' : '· $readers',
      openable: p.kind == SceneParamKind.list,
      tooltip: '${paramKindLabel(p.kind)} · ${p.typeName}',
      onOpen: () => editor.aside = aside,
      menu: () => paramMenu(
        editor,
        p,
        onRename: () => setState(() => _renaming = aside),
      ),
      rename: (wanted) => editor.renameParam(p.name, wanted),
    );
  }

  Widget _motionRow(BuildContext context, String name) {
    var aside = MotionAside(name);
    var m = editor.motions[name]!;
    var seconds = m.durationOf(m.timeline).inMilliseconds / 1000;
    return _row(
      context,
      aside,
      icon: Icons.play_arrow_outlined,
      name: name,
      trailing: '${seconds.toStringAsFixed(2)}s',
      openable: true,
      opened: editor.activeMotion == name,
      tooltip: '${m.groups.length} groups · on ${m.sceneClassName}',
      onOpen: () => _open(name),
      menu: () => [
        MenuItem(
          editor.activeMotion == name
              ? 'Timeline is open'
              : 'Open the timeline',
          icon: Icons.keyboard_arrow_down,
          onSelected: editor.activeMotion == name ? null : () => _open(name),
        ),
        MenuItem(
          'Rename',
          icon: Icons.edit_outlined,
          shortcut: 'double-click',
          onSelected: () => setState(() => _renaming = aside),
        ),
        const MenuDivider(),
        MenuItem(
          'Delete $name',
          icon: Icons.close,
          danger: true,
          onSelected: () => editor.removeMotion(name),
        ),
      ],
      rename: (wanted) => editor.renameMotion(name, wanted),
    );
  }

  void _open(String motion) {
    editor.aside = MotionAside(motion);
    if (widget.onOpenMotion case var open?) {
      open(motion);
    } else {
      editor.activeMotion = motion;
    }
  }

  Widget _row(
    BuildContext context,
    SceneAside aside, {
    required IconData icon,
    required String name,
    required String trailing,
    required bool openable,
    bool opened = false,
    required String tooltip,
    required VoidCallback onOpen,
    required List<MenuEntry> Function() menu,
    required void Function(String wanted) rename,
  }) {
    var colors = context.colors;
    var selected = editor.aside == aside;
    var renaming = _renaming == aside;
    return GestureDetector(
      onSecondaryTapDown: (d) {
        editor.aside = aside;
        showContextMenu(context, d.globalPosition, menu());
      },
      onDoubleTap: () => setState(() => _renaming = aside),
      child: FwTreeRow(
        depth: 1,
        density: TreeRowDensity.roomy,
        selected: selected,
        onTap: () => editor.aside = aside,
        label: Row(
          spacing: FwSpacing.sm,
          children: [
            Icon(
              icon,
              size: FwIconSize.sm,
              color: selected ? colors.accentDark : colors.mut,
            ),
            Expanded(
              child: renaming
                  ? InlineNameField(
                      initial: name,
                      dense: true,
                      style: context.type.body,
                      onCommit: (wanted) {
                        try {
                          rename(wanted);
                        } on ArgumentError catch (e) {
                          return '${e.message}';
                        }
                        setState(() => _renaming = null);
                        return null;
                      },
                      onCancel: () => setState(() => _renaming = null),
                    )
                  : Tooltip(
                      message: tooltip,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.body.copyWith(
                          color: selected ? colors.accentDark : colors.ink,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        trailing: [
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: context.type.caption.copyWith(color: colors.mut2),
            ),
          if (openable)
            Tooltip(
              message: opened ? 'Open below' : 'Open below the canvas',
              child: Tappable(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
                child: Padding(
                  padding: const EdgeInsets.all(FwSpacing.xxs),
                  child: Icon(
                    Icons.chevron_right,
                    size: FwIconSize.sm,
                    color: opened ? colors.accent : colors.mut2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _addParamMenu(BuildContext context, Offset at) {
    showContextMenu(context, at, [
      const MenuHeader('New parameter'),
      for (var (kind, label, type) in paramKinds)
        MenuItem(
          label,
          shortcut: type,
          onSelected: () {
            var name = editor.freeParamName(kind.name);
            editor.addParam(name, kind);
            var aside = ParamAside(name);
            editor.aside = aside;
            setState(() {
              _paramsOpen = true;
              _renaming = aside;
            });
          },
        ),
    ]);
  }
}
