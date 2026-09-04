import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/context_menu.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../externals_file.dart';
import '../playback.dart';
import 'canvas.dart';
import 'inline_name.dart';
import 'inspector.dart';
import 'shortcuts.dart';
import 'timeline.dart';
import 'tree_panel.dart';

/// The scene workspace: tree · canvas over timeline · inspector.
///
/// One surface, decided 2026-09-01 over two alternatives (Design/Animate
/// modes, a timeline drawer) built as catalog demos and looked at. The
/// argument that won: selection is one set across the tree, the canvas and
/// the lanes — a timeline row *is* a scene node — so nothing that shows the
/// nodes should leave when the keys arrive.
///
/// The scene is static first: the timeline appears only once a motion is
/// opened from the strip under the canvas, and a scene may have several.
///
/// Tree and canvas share the editing focus scope; the timeline has its own
/// (an arrow means something else to a key); the inspector sits outside both,
/// so its fields keep every keystroke.
class SceneWorkspaceView extends StatefulWidget {
  const SceneWorkspaceView(
    this.editor, {
    super.key,
    this.content,
    required this.playbackFor,
    this.sceneClassName,
    this.status,
    this.onEnterNested,
    this.canvasTrailing = const [],
    this.pane,
    this.externals = const [],
  });

  final SceneEditor editor;

  /// The widgets the app declares — see [SceneInspector.externals].
  final List<ExternalWidgetDecl> externals;

  /// The renderer, sized to the artboard — see [SceneCanvas.content].
  final Widget? content;

  /// The playback for one of the editor's motions, by name — made once and
  /// kept by the host, because a playback owns a ticker.
  final ScenePlayback Function(String motion) playbackFor;

  /// What a new motion animates; null hides "New motion".
  final String? sceneClassName;

  final ValueListenable<String>? status;

  /// Drill into a nested scene — the workspace's `enter`, when there is one.
  final ValueChanged<SceneNode>? onEnterNested;

  /// Controls the host wants on the canvas bar's right — a guest reload.
  final List<Widget> canvasTrailing;

  /// A pane-sized picture under the artboard — see [SceneCanvas.pane].
  final Widget Function(
    BuildContext context,
    Matrix4 view,
    Size pane,
    Size artboard,
  )?
  pane;

  static const treeWidth = 230.0;
  static const inspectorWidth = 290.0;

  @override
  State<SceneWorkspaceView> createState() => _SceneWorkspaceViewState();
}

class _SceneWorkspaceViewState extends State<SceneWorkspaceView> {
  /// Leaves the open motion: playback stops (the scene shows as authored),
  /// recording ends, no chip is active. The chevron; there is no folding a
  /// motion away while it stays on the picture — static first.
  void _closeMotion() {
    var active = editor.activeMotion;
    if (active == null) return;
    widget.playbackFor(active).stop();
    editor.autoKey = false;
    editor.activeMotion = null;
  }

  SceneEditor get editor => widget.editor;

  @override
  Widget build(BuildContext context) {
    var line = context.colors.line;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: EditorShortcuts(
            editor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: SceneWorkspaceView.treeWidth,
                  child: SceneTreePanel(
                    editor,
                    onEnterNested: widget.onEnterNested,
                  ),
                ),
                Container(width: 1, color: line),
                Expanded(
                  child: AnimatedBuilder(
                    animation: editor.listenable,
                    builder: (context, _) {
                      var active = editor.activeMotion;
                      var open = active != null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SceneCanvas(
                              editor,
                              content: widget.content,
                              status: widget.status,
                              onEnterNested: widget.onEnterNested,
                              trailing: widget.canvasTrailing,
                              pane: widget.pane,
                            ),
                          ),
                          Container(height: 1, color: line),
                          _MotionStrip(
                            editor: editor,
                            sceneClassName: widget.sceneClassName,
                            onClose: active == null ? null : _closeMotion,
                            onPick: (name) {
                              editor.activeMotion = name;
                              // A motion that was closed comes back on the
                              // picture; one already open is unchanged.
                              widget.playbackFor(name).apply();
                            },
                          ),
                          if (open) ...[
                            Container(height: 1, color: line),
                            Expanded(
                              flex: 2,
                              child: SceneTimeline(
                                editor,
                                widget.playbackFor(active),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(width: 1, color: line),
        SizedBox(
          width: SceneWorkspaceView.inspectorWidth,
          // The inspector shows whatever is selected now; the other panels
          // subscribe for themselves, this one is stateless over the editor.
          child: AnimatedBuilder(
            animation: Listenable.merge([
              editor.listenable,
              editor.doc.listenable,
            ]),
            builder: (context, _) =>
                SceneInspector(editor, externals: widget.externals),
          ),
        ),
      ],
    );
  }
}

/// The scene's motions, as a strip under the canvas: pick one to open its
/// timeline, make a new one, fold the timeline away. The static editor is
/// the resting state; this is the door to animation.
class _MotionStrip extends StatefulWidget {
  const _MotionStrip({
    required this.editor,
    required this.sceneClassName,
    required this.onClose,
    required this.onPick,
  });

  final SceneEditor editor;
  final String? sceneClassName;

  /// Closes the open motion; null when none is.
  final VoidCallback? onClose;
  final ValueChanged<String> onPick;

  @override
  State<_MotionStrip> createState() => _MotionStripState();
}

class _MotionStripState extends State<_MotionStrip> {
  /// The chip being renamed, by its current name.
  String? _renaming;

  SceneEditor get editor => widget.editor;

  String? _rename(String name, String wanted) {
    if (_renaming != name) return null;
    try {
      editor.renameMotion(name, wanted);
      setState(() => _renaming = null);
      return null;
    } on ArgumentError catch (e) {
      return e.message as String?;
    }
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;
    var active = editor.activeMotion;
    var names = editor.motions.keys.toList();
    var sceneClassName = widget.sceneClassName;
    var onClose = widget.onClose;
    var onPick = widget.onPick;
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
                : 'Close the motion — the scene as authored',
            child: Tappable(
              onTap: onClose,
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.xs),
                child: Icon(
                  active == null
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: FwIconSize.md,
                  color: onClose == null ? colors.mut3 : colors.ink,
                ),
              ),
            ),
          ),
          Text('Motions', style: type.sectionLabel),
          if (names.isEmpty)
            Text('none yet', style: type.caption.copyWith(color: colors.mut2)),
          for (var name in names)
            GestureDetector(
              onSecondaryTapUp: (d) =>
                  showContextMenu(context, d.globalPosition, [
                    MenuItem(
                      'Rename $name…',
                      icon: Icons.edit_outlined,
                      onSelected: () => setState(() => _renaming = name),
                    ),
                    MenuItem(
                      'Delete $name',
                      icon: Icons.close,
                      danger: true,
                      onSelected: () => editor.removeMotion(name),
                    ),
                  ]),
              child: Tappable(
                onTap: _renaming == name ? null : () => onPick(name),
                borderRadius: BorderRadius.circular(context.radii.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.md,
                    vertical: FwSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: name == active ? colors.accentSoft : null,
                    border: Border.all(
                      color: name == active ? colors.accent : colors.line,
                    ),
                    borderRadius: BorderRadius.circular(context.radii.pill),
                  ),
                  child: _renaming == name
                      ? SizedBox(
                          width: 160,
                          child: InlineNameField(
                            initial: name,
                            dense: true,
                            style: type.caption,
                            onCommit: (wanted) => _rename(name, wanted),
                            onCancel: () => setState(() => _renaming = null),
                          ),
                        )
                      : Text(
                          name,
                          style: type.caption.copyWith(
                            color: name == active
                                ? colors.accentDark
                                : colors.ink,
                          ),
                        ),
                ),
              ),
            ),
          if (sceneClassName case var className?)
            Tooltip(
              message: 'A new, empty motion on this scene',
              child: Tappable(
                onTap: () => onPick(editor.addMotion(className)),
                borderRadius: BorderRadius.circular(context.radii.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FwSpacing.sm,
                    vertical: FwSpacing.xxs,
                  ),
                  child: Row(
                    spacing: FwSpacing.xxs,
                    children: [
                      Icon(Icons.add, size: FwIconSize.xs, color: colors.mut),
                      Text(
                        'New motion',
                        style: type.caption.copyWith(color: colors.mut),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
