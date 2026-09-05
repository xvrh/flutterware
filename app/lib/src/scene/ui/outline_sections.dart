import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../../ui/tree_row.dart';
import '../editor.dart';
import 'inline_name.dart';
import 'param_pane.dart';

/// The rest of what the file declares, under the layers: its parameters and
/// its motions, each a section with a count and its own `+`.
///
/// A click OPENS a row in the drawer under the canvas — a motion's
/// timeline, a parameter's pane or table — and the open one is the
/// highlighted one. One verb, because the drawer is independent of the node
/// selection: it stays put while nodes are clicked on the canvas to key
/// them, so there was nothing a separate "select" had to protect. Rename in
/// place with a double-click on the name; right-click for the rest.
class SceneOutlineSections extends StatefulWidget {
  const SceneOutlineSections(
    this.editor, {
    super.key,
    this.sceneClassName,
    this.onOpenMotion,
    this.onOpenParam,
  });

  final SceneEditor editor;

  /// What a new motion animates; null hides the motions' `+`.
  final String? sceneClassName;

  /// Opens a motion's timeline — the workspace's door, which also starts
  /// its playback.
  final ValueChanged<String>? onOpenMotion;

  /// Opens a parameter below the canvas.
  final ValueChanged<String>? onOpenParam;

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

  /// The last row tapped and when: a second tap on it within the double-tap
  /// window renames. Detected by hand rather than with a double-tap
  /// recognizer, which would hold every single tap for 300ms — selection
  /// has to be instant. The same rule as the layers above.
  (SceneAside, DateTime)? _lastTap;

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
        left: FwSpacing.md + FwSpacing.xxs,
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
      tooltip: '${paramKindLabel(p.kind)} · ${p.typeName}',
      onOpen: () => _openParam(p.name),
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
      tooltip: '${m.groups.length} groups · on ${m.sceneClassName}',
      onOpen: () => _open(name),
      menu: () => [
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
    if (widget.onOpenMotion case var open?) {
      open(motion);
    } else {
      editor.activeMotion = motion;
    }
  }

  void _openParam(String name) {
    if (widget.onOpenParam case var open?) {
      open(name);
    } else {
      editor.openParam = name;
    }
  }

  Widget _row(
    BuildContext context,
    SceneAside aside, {
    required IconData icon,
    required String name,
    required String trailing,
    required String tooltip,
    required VoidCallback onOpen,
    required List<MenuEntry> Function() menu,
    required void Function(String wanted) rename,
  }) {
    var colors = context.colors;
    var open = editor.drawer == aside;
    var renaming = _renaming == aside;
    return GestureDetector(
      onSecondaryTapDown: (d) =>
          showContextMenu(context, d.globalPosition, menu()),
      child: FwTreeRow(
        // One level under the section's own line, whose chevron is in the
        // leading slot the way a frame's is: the kind's icon takes that
        // slot here, so a row reads as the section's child, not a
        // grandchild.
        depth: 0,
        density: TreeRowDensity.roomy,
        selected: open,
        onTap: () {
          var now = DateTime.now();
          var again =
              _lastTap?.$1 == aside &&
              now.difference(_lastTap!.$2) < kDoubleTapTimeout;
          _lastTap = (aside, now);
          if (again) {
            setState(() => _renaming = aside);
            return;
          }
          onOpen();
        },
        leading: Icon(
          icon,
          size: FwIconSize.sm,
          color: open ? colors.accentDark : colors.mut,
        ),
        label: renaming
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
                    color: open ? colors.accentDark : colors.ink,
                  ),
                ),
              ),
        trailing: [
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: context.type.caption.copyWith(color: colors.mut2),
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
            _openParam(name);
            setState(() {
              _paramsOpen = true;
              _renaming = ParamAside(name);
            });
          },
        ),
    ]);
  }
}
