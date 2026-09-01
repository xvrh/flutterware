// The workspace: what the editor has open, and how you move through it.
//
// A scene FILE is one document — a scene class and the motions animating it
// (grammar 0.5) — so [SceneFile] holds the parsed pair, the editor state
// over it, and the save door. A [SceneWorkspace] holds the file you opened
// and the stack you drilled into: entering a nested scene switches the whole
// surface and leaves a breadcrumb, because an instance's internals are not
// addressable from its parent (the nesting law).
//
// Pure Dart, like the editor beside it: the fw CLI and a codemod open files
// through the same door the GUI does.
import 'package:flutterware/scene_authoring.dart';

import 'editor.dart';
import 'scene_file.dart';

/// One open file: the pair, its editor, and where it came from.
class SceneFile {
  SceneFile({
    required this.path,
    required this.className,
    required SceneDocument scene,
    Map<String, MotionDocument> motions = const {},
  }) : editor = SceneEditor(scene, motions: motions);

  /// Read a file through the parse door. Refusals are the collecting kind,
  /// so a rejected file yields no document and every reason is listed.
  static SceneFileOpen open(String path, String source) {
    var parsed = parseSceneFile(source);
    if (!parsed.ok) return SceneFileOpen._(null, parsed.refusals);
    return SceneFileOpen._(
      SceneFile(
        path: path,
        className: parsed.className!,
        scene: parsed.doc!,
        motions: parsed.motions,
      ),
      const [],
    );
  }

  /// Where it lives — the identity a workspace dedupes on.
  final String path;

  /// The scene class, which is also the file's name in the UI.
  final String className;

  final SceneEditor editor;

  SceneDocument get scene => editor.doc;
  Map<String, MotionDocument> get motions => editor.motions;

  var _savedRevision = 0;

  /// Whether the file differs from what was last written. Counted off the
  /// editor's revision, so undoing back to the saved state still reads
  /// dirty — the safe direction to be wrong in.
  bool get isDirty => editor.revision != _savedRevision;

  /// The text to write. Emitting through the door and parsing the result
  /// back is the caller's job — [save] does it.
  String emit() => emitSceneFile(scene, className: className, motions: motions);

  /// Emit, refuse to write anything the parser would reject, and hand the
  /// text to [write]. Returns the refusals — empty on success.
  List<SceneRefusal> save(void Function(String path, String source) write) {
    var source = emit();
    var check = parseSceneFile(source);
    if (!check.ok) return check.refusals;
    write(path, source);
    _savedRevision = editor.revision;
    return const [];
  }
}

/// The result of opening a file: the document, or why there is none.
class SceneFileOpen {
  SceneFileOpen._(this.file, this.refusals);

  final SceneFile? file;
  final List<SceneRefusal> refusals;

  bool get ok => file != null;
}

/// One step of the breadcrumb: a file, and the node in its parent that
/// stands for it (null for the file you opened).
class SceneCrumb {
  SceneCrumb(this.file, this.viaNode);

  final SceneFile file;

  /// The nested node's name in the parent — what the breadcrumb labels the
  /// step with, and what an exit selects on the way back.
  final String? viaNode;
}

/// Resolves the file a nested node stands for. Nesting is not in the grammar
/// yet (milestone 6), so the workspace takes this as a hook: the plugin will
/// pass one that finds the pair by scene class, and a test passes a fake.
typedef NestedSceneResolver = SceneFile? Function(SceneNode node);

class SceneWorkspace extends SceneListenable {
  SceneWorkspace(SceneFile root, {this.resolveNested})
    : _stack = [SceneCrumb(root, null)],
      _opened = {root.path: root};

  final List<SceneCrumb> _stack;

  /// Every file this workspace has opened, by path — NOT just the ones on
  /// the breadcrumb. Leaving a nested scene must not lose sight of edits
  /// made inside it; they are unsaved work either way.
  final Map<String, SceneFile> _opened;

  final NestedSceneResolver? resolveNested;

  /// The breadcrumb, outermost first — the file you opened, then every
  /// nested scene entered since.
  List<SceneCrumb> get crumbs => List.unmodifiable(_stack);

  /// The file being edited: the deepest crumb. Everything on screen —
  /// canvas, tree, inspector, timeline — reads this one.
  SceneFile get active => _stack.last.file;

  SceneEditor get editor => active.editor;

  bool get isNested => _stack.length > 1;

  /// Every file this workspace has opened, in the order it opened them.
  Iterable<SceneFile> get openFiles => _opened.values;

  /// The files with unsaved work — what a save-all button writes and what an
  /// exit guard warns about. Includes nested scenes already left behind.
  Iterable<SceneFile> get dirtyFiles => _opened.values.where((f) => f.isDirty);

  bool get anyDirty => dirtyFiles.isNotEmpty;

  /// Drill into the scene [node] stands for. Refuses loudly rather than
  /// silently doing nothing: a node that is not a nested scene, or one whose
  /// file cannot be resolved, is a bug in the caller, not a user error.
  void enter(SceneNode node) {
    var resolve = resolveNested;
    if (resolve == null) {
      throw StateError(
        'this workspace cannot enter nested scenes — it was built without a '
        'resolver, so nothing can say which file "${node.name}" stands for',
      );
    }
    var file = resolve(node);
    if (file == null) {
      throw ArgumentError(
        '"${node.name}" is not a nested scene — only a node standing for '
        'another scene file can be entered',
      );
    }
    _opened.putIfAbsent(file.path, () => file);
    _stack.add(SceneCrumb(file, node.name));
    notifyListeners();
  }

  /// Leave the current scene, selecting the node you came in through so the
  /// parent picks up where you left it. No-op at the root.
  void exit() {
    if (_stack.length < 2) return;
    var leaving = _stack.removeLast();
    var via = leaving.viaNode;
    if (via != null) {
      var node = active.scene.nodeNamed(via);
      if (node != null) editor.select(node);
    }
    notifyListeners();
  }

  /// Jump to a crumb — the breadcrumb's own click, which pops everything
  /// deeper in one step.
  void goTo(int index) {
    if (index < 0 || index >= _stack.length - 1) return;
    _stack.removeRange(index + 1, _stack.length);
    notifyListeners();
  }
}
