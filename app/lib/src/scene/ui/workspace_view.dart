import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
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
/// Tree and canvas share the editing focus scope; the timeline has its own
/// (an arrow means something else to a key); the inspector sits outside both,
/// so its fields keep every keystroke.
class SceneWorkspaceView extends StatelessWidget {
  const SceneWorkspaceView(
    this.editor, {
    super.key,
    required this.content,
    this.playback,
    this.status,
    this.onEnterNested,
    this.canvasTrailing = const [],
  });

  final SceneEditor editor;

  /// The renderer, sized to the artboard — see [SceneCanvas.content].
  final Widget content;

  /// The motion being edited, or null for a scene with none: then there is
  /// no timeline, and the canvas takes the height.
  final ScenePlayback? playback;

  final ValueListenable<String>? status;

  /// Drill into a nested scene — the workspace's `enter`, when there is one.
  final ValueChanged<SceneNode>? onEnterNested;

  /// Controls the host wants on the canvas bar's right — a guest reload.
  final List<Widget> canvasTrailing;

  static const treeWidth = 230.0;
  static const inspectorWidth = 290.0;

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
                  width: treeWidth,
                  child: SceneTreePanel(editor, onEnterNested: onEnterNested),
                ),
                Container(width: 1, color: line),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: SceneCanvas(
                          editor,
                          content: content,
                          status: status,
                          onEnterNested: onEnterNested,
                          trailing: canvasTrailing,
                        ),
                      ),
                      if (playback case var playback?) ...[
                        Container(height: 1, color: line),
                        Expanded(
                          flex: 2,
                          child: SceneTimeline(editor, playback),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(width: 1, color: line),
        SizedBox(
          width: inspectorWidth,
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
