import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/tappable.dart';
import '../editor.dart';
import '../playback.dart';
import 'canvas.dart';
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
    required this.content,
    required this.playbackFor,
    this.sceneClassName,
    this.status,
    this.onEnterNested,
    this.canvasTrailing = const [],
  });

  final SceneEditor editor;

  /// The renderer, sized to the artboard — see [SceneCanvas.content].
  final Widget content;

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

  static const treeWidth = 230.0;
  static const inspectorWidth = 290.0;

  @override
  State<SceneWorkspaceView> createState() => _SceneWorkspaceViewState();
}

class _SceneWorkspaceViewState extends State<SceneWorkspaceView> {
  /// The timeline folded away while a motion stays open — the chevron.
  var _folded = false;

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
                      var open = active != null && !_folded;
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
                            ),
                          ),
                          Container(height: 1, color: line),
                          _MotionStrip(
                            editor: editor,
                            sceneClassName: widget.sceneClassName,
                            folded: _folded,
                            onFold: active == null
                                ? null
                                : () => setState(() => _folded = !_folded),
                            onPick: (name) {
                              editor.activeMotion = name;
                              setState(() => _folded = false);
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
            builder: (context, _) => SceneInspector(editor),
          ),
        ),
      ],
    );
  }
}

/// The scene's motions, as a strip under the canvas: pick one to open its
/// timeline, make a new one, fold the timeline away. The static editor is
/// the resting state; this is the door to animation.
class _MotionStrip extends StatelessWidget {
  const _MotionStrip({
    required this.editor,
    required this.sceneClassName,
    required this.folded,
    required this.onFold,
    required this.onPick,
  });

  final SceneEditor editor;
  final String? sceneClassName;
  final bool folded;
  final VoidCallback? onFold;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;
    var active = editor.activeMotion;
    var names = editor.motions.keys.toList();
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
                : folded
                ? 'Show the timeline'
                : 'Hide the timeline',
            child: Tappable(
              onTap: onFold,
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.xs),
                child: Icon(
                  active == null || folded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: FwIconSize.md,
                  color: onFold == null ? colors.mut3 : colors.ink,
                ),
              ),
            ),
          ),
          Text('Motions', style: type.sectionLabel),
          if (names.isEmpty)
            Text('none yet', style: type.caption.copyWith(color: colors.mut2)),
          for (var name in names)
            Tappable(
              onTap: () => onPick(name),
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
                child: Text(
                  name,
                  style: type.caption.copyWith(
                    color: name == active ? colors.accentDark : colors.ink,
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
