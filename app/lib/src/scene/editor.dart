// The editor-state layer between the document and the widgets — the
// foundation milestone 2 of the graduation plan builds everything else on.
// The document stays pure domain; everything about *editing* it lives here:
// selection (a set of node NAMES — names survive undo replacing the node
// objects), hover, and the command door every mutation passes through,
// which is what makes the undo stack a journal instead of a wish.
//
// Pure Dart on purpose: a codemod or the fw CLI can drive the same doors
// the GUI does, and the purity wall (test/scene_pure_test.dart) holds it.
import 'package:flutterware/scene_authoring.dart';

/// One undo journal entry: what the document looked like before the door
/// ran, and the label the UI shows.
class _JournalEntry {
  _JournalEntry(this.label, this.before, this.mergeKey);

  final String label;
  final SceneSnapshot before;
  final String? mergeKey;
}

class SceneEditor extends SceneListenable {
  SceneEditor(this.doc);

  final SceneDocument doc;

  // -------------------------------------------------------------------------
  // Selection — a set of node names, in selection order.
  // -------------------------------------------------------------------------

  final _selection = <String>{};

  /// Names may outlive their nodes (undo, delete); reads resolve against
  /// the live document and silently drop the dead.
  Iterable<SceneNode> get selectedNodes =>
      _selection.map(doc.nodeNamed).whereType<SceneNode>();

  Iterable<String> get selectionNames =>
      selectedNodes.map((n) => n.name).toList();

  bool isSelected(SceneNode node) => _selection.contains(node.name);

  /// The node the inspector shows: the most recently selected live one.
  SceneNode? get primary {
    SceneNode? last;
    for (var node in selectedNodes) {
      last = node;
    }
    return last;
  }

  /// Exactly one live node selected, or null — what a resize handle needs.
  SceneNode? get single {
    var nodes = selectedNodes.toList();
    return nodes.length == 1 ? nodes.first : null;
  }

  /// Replace the selection ([toggle] false) or flip [node]'s membership.
  /// The root is the artboard, not a selectable node.
  void select(SceneNode? node, {bool toggle = false}) {
    if (node == null || node == doc.root) {
      if (toggle) return;
      clearSelection();
      return;
    }
    if (toggle) {
      if (!_selection.remove(node.name)) _selection.add(node.name);
    } else {
      _selection
        ..clear()
        ..add(node.name);
    }
    notifyListeners();
  }

  /// Marquee: the selection becomes the top-level nodes whose measured
  /// rect overlaps [rect] — geometry policy here, the gesture in the
  /// widget.
  void selectWithin(SceneRect rect) {
    setSelection([
      for (var node in doc.root.children)
        if (node.measured case var m? when m.overlaps(rect)) node.name,
    ]);
  }

  void setSelection(Iterable<String> names) {
    _selection
      ..clear()
      ..addAll(names);
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  String? _hover;

  String? get hover => _hover;

  set hover(String? name) {
    if (_hover == name) return;
    _hover = name;
    notifyListeners();
  }

  /// Nodes the canvas exposes to the pointer, bottom-to-top: top-level
  /// children always, plus the children of every selected node's frame
  /// chain. Selection determines hit-test structure — the click ladder is
  /// plain z-order, no coordinate math in the editor.
  Iterable<SceneNode> addressable() {
    var seen = <SceneNode>{};
    var out = <SceneNode>[];
    void addAll(Iterable<SceneNode> nodes) {
      for (var n in nodes) {
        if (seen.add(n)) out.add(n);
      }
    }

    addAll(doc.root.children);
    for (var sel in selectedNodes) {
      var chain = <FrameNode>[];
      var p = doc.parentOf(sel);
      while (p != null && p != doc.root) {
        chain.insert(0, p);
        p = doc.parentOf(p);
      }
      if (sel is FrameNode) chain.add(sel);
      for (var f in chain) {
        addAll(f.children);
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // The command door and its journal.
  // -------------------------------------------------------------------------

  static const _journalCap = 100;

  final _undo = <_JournalEntry>[];
  final _redo = <_JournalEntry>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  /// Every mutation of the document goes through here: snapshot, mutate
  /// inside one [SceneDocument.edit], journal. A [mergeKey] coalesces a
  /// burst of consecutive same-key doors (a drag's move deltas, a field's
  /// live keystrokes) into ONE undo entry — the first snapshot of the burst
  /// is the one undo restores.
  void perform(String label, void Function() mutate, {String? mergeKey}) {
    var merge =
        mergeKey != null &&
        _redo.isEmpty &&
        _undo.isNotEmpty &&
        _undo.last.mergeKey == mergeKey;
    if (!merge) {
      _undo.add(_JournalEntry(label, doc.snapshot(), mergeKey));
      if (_undo.length > _journalCap) _undo.removeAt(0);
      _redo.clear();
    }
    doc.edit(mutate);
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    var entry = _undo.removeLast();
    _redo.add(_JournalEntry(entry.label, doc.snapshot(), null));
    doc.restore(entry.before);
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    var entry = _redo.removeLast();
    _undo.add(_JournalEntry(entry.label, doc.snapshot(), null));
    doc.restore(entry.before);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Editing verbs, all doors.
  // -------------------------------------------------------------------------

  void deleteSelection() {
    var nodes = selectedNodes.toList();
    if (nodes.isEmpty) return;
    perform('Delete ${_count(nodes)}', () {
      for (var node in nodes) {
        doc.parentOf(node)?.children.remove(node);
      }
    });
    clearSelection();
  }

  /// Move every selected node under an absolute parent by (dx, dy). One
  /// gesture is one entry: pass the gesture's [mergeKey].
  void nudgeSelection(double dx, double dy, {String? mergeKey}) {
    var nodes = [
      for (var node in selectedNodes)
        if (doc.parentOf(node)?.layout == NodeLayout.absolute) node,
    ];
    if (nodes.isEmpty) return;
    perform('Move ${_count(nodes)}', mergeKey: mergeKey, () {
      for (var node in nodes) {
        node.x += dx;
        node.y += dy;
      }
    });
  }

  /// Copy every selected node beside its original, offset a hair so the
  /// copy is visible. The whole subtree gets fresh names — names are field
  /// identity, unique per scene.
  void duplicateSelection() {
    var nodes = selectedNodes.toList();
    if (nodes.isEmpty) return;
    var copies = <SceneNode>[];
    perform('Duplicate ${_count(nodes)}', () {
      var taken = {for (var (n, _) in doc.walk()) n.name};
      String fresh(String base) {
        var i = 1;
        while (taken.contains('$base$i')) {
          i++;
        }
        var name = '$base$i';
        taken.add(name);
        return name;
      }

      for (var node in nodes) {
        var parent = doc.parentOf(node);
        if (parent == null) continue;
        var copy = deepCopyNode(node, rename: fresh)
          ..x += 10
          ..y += 10;
        parent.children.insert(parent.children.indexOf(node) + 1, copy);
        copies.add(copy);
      }
    });
    setSelection([for (var c in copies) c.name]);
  }

  String _count(List<SceneNode> nodes) =>
      nodes.length == 1 ? nodes.first.name : '${nodes.length} nodes';
}
