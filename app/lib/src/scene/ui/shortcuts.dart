import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor.dart';

/// The scene editing focus scope: keyboard verbs for whatever it wraps.
///
/// Owns its focus node, and any pointer-down inside takes the keyboard back
/// — a press in the inspector (which sits outside) leaves it there, so a
/// Backspace in a field never deletes a node. The node is this widget's own
/// rather than `Focus.of(context)`, because the nearest Focus is whatever
/// happens to be nearest — a Scrollable brings one — and focus returned to
/// the wrong one is how cmd-Z reached a text field's built-in undo and beeped.
class EditorShortcuts extends StatefulWidget {
  const EditorShortcuts(this.editor, {super.key, required this.child});

  final SceneEditor editor;
  final Widget child;

  @override
  State<EditorShortcuts> createState() => _EditorShortcutsState();
}

class _EditorShortcutsState extends State<EditorShortcuts> {
  final _node = FocusNode(debugLabel: 'scene editor');

  SceneEditor get editor => widget.editor;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var arrows = <ShortcutActivator, VoidCallback>{};
    for (var (key, dx, dy) in [
      (LogicalKeyboardKey.arrowLeft, -1.0, 0.0),
      (LogicalKeyboardKey.arrowRight, 1.0, 0.0),
      (LogicalKeyboardKey.arrowUp, 0.0, -1.0),
      (LogicalKeyboardKey.arrowDown, 0.0, 1.0),
    ]) {
      arrows[SingleActivator(key)] = () =>
          editor.nudgeSelection(dx, dy, mergeKey: 'nudge');
      arrows[SingleActivator(key, shift: true)] = () =>
          editor.nudgeSelection(dx * 10, dy * 10, mergeKey: 'nudge');
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): editor.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            editor.redo,
        const SingleActivator(LogicalKeyboardKey.backspace):
            editor.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.delete):
            editor.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          editor.tool = SceneTool.select;
          editor.clearSelection();
        },
        // The drawing tools, as the letter each is known by in every editor
        // of this kind. Plain letters are safe here: the inspector's fields
        // sit outside this scope.
        const SingleActivator(LogicalKeyboardKey.keyV): () =>
            editor.tool = SceneTool.select,
        const SingleActivator(LogicalKeyboardKey.keyF): () =>
            editor.tool = SceneTool.frame,
        const SingleActivator(LogicalKeyboardKey.keyT): () =>
            editor.tool = SceneTool.text,
        const SingleActivator(LogicalKeyboardKey.keyS): () =>
            editor.tool = SceneTool.shape,
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            editor.duplicateSelection,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () => editor
            .setSelection([for (var n in editor.doc.root.children) n.name]),
        ...arrows,
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _node.requestFocus(),
        child: Focus(focusNode: _node, autofocus: true, child: widget.child),
      ),
    );
  }
}
