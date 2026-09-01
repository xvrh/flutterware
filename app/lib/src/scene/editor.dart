// The editor-state layer between the document and the widgets — the
// foundation milestone 2 of the graduation plan builds everything else on.
// The document stays pure domain; everything about *editing* it lives here:
// selection in two domains (node NAMES on the scene, key REFS on the
// timeline — both survive undo, because a name and a key id outlive the
// objects a restore touches), hover, and the command door every mutation
// passes through, which is what makes the undo stack a journal instead of
// a wish. Scene and motions are one document here: one journal, one undo.
//
// Pure Dart on purpose: a codemod or the fw CLI can drive the same doors
// the GUI does, and the purity wall (test/scene_pure_test.dart) holds it.
import 'package:flutterware/scene_authoring.dart';

/// One undo journal entry: what the file looked like before the door ran,
/// and the label the UI shows. Both planes ride together — a timeline edit
/// and a layout edit undo through the same journal, because they are one
/// document.
class _JournalEntry {
  _JournalEntry(this.label, this.scene, this.motions, this.mergeKey);

  final String label;
  final SceneSnapshot scene;
  final Map<String, MotionSnapshot> motions;
  final String? mergeKey;
}

/// Where a key lives: which motion, which group, which track. The key
/// itself is held by [MotionKey.id], which survives sorting and undo.
class MotionKeyRef {
  const MotionKeyRef(this.motion, this.group, this.prop, this.keyId);

  final String motion;
  final String group;

  /// The track's property — an arg track is spelled `args.<name>`, the way
  /// the fx plane spells it.
  final String prop;

  final int keyId;

  @override
  bool operator ==(Object other) =>
      other is MotionKeyRef &&
      other.motion == motion &&
      other.group == group &&
      other.prop == prop &&
      other.keyId == keyId;

  @override
  int get hashCode => Object.hash(motion, group, prop, keyId);

  @override
  String toString() => '$motion.$group.$prop#$keyId';
}

class SceneEditor extends SceneListenable {
  SceneEditor(this.doc, {Map<String, MotionDocument> motions = const {}})
    : motions = {...motions};

  final SceneDocument doc;

  /// The motions of the file, by class name — the same document as the
  /// scene, so they share this editor's selection, doors and journal.
  final Map<String, MotionDocument> motions;

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
    _keySelection.clear();
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
    if (_selection.isNotEmpty) _keySelection.clear();
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
  // Selection, second domain: keys on the timeline.
  // -------------------------------------------------------------------------

  final _keySelection = <MotionKeyRef>{};

  /// The two domains do not mix: selecting a node clears the key selection
  /// and vice versa, because every verb (nudge, delete, duplicate) means a
  /// different thing in each, and a verb must never be ambiguous about what
  /// it acts on.
  Iterable<MotionKeyRef> get selectedKeys =>
      _keySelection.where((ref) => keyOf(ref) != null);

  bool isKeySelected(MotionKeyRef ref) => _keySelection.contains(ref);

  /// Resolve a ref against the live model, or null if it no longer exists
  /// (deleted, or undone away) — the same lazy-prune rule node names get.
  MotionKey? keyOf(MotionKeyRef ref) {
    var track = trackOf(ref.motion, ref.group, ref.prop);
    if (track == null) return null;
    for (var key in track.keys) {
      if (key.id == ref.keyId) return key;
    }
    return null;
  }

  MotionTrack? trackOf(String motion, String group, String prop) {
    var g = motions[motion]?.groupNamed(group);
    if (g == null) return null;
    return prop.startsWith('args.')
        ? g.args[prop.substring(5)]
        : g.tracks[prop];
  }

  void selectKey(MotionKeyRef? ref, {bool toggle = false}) {
    if (ref == null) {
      if (!toggle) clearKeySelection();
      return;
    }
    if (toggle) {
      if (!_keySelection.remove(ref)) _keySelection.add(ref);
    } else {
      _keySelection
        ..clear()
        ..add(ref);
    }
    _selection.clear();
    notifyListeners();
  }

  void setKeySelection(Iterable<MotionKeyRef> refs) {
    _keySelection
      ..clear()
      ..addAll(refs);
    if (_keySelection.isNotEmpty) _selection.clear();
    notifyListeners();
  }

  void clearKeySelection() {
    if (_keySelection.isEmpty) return;
    _keySelection.clear();
    notifyListeners();
  }

  /// Move every selected key in time, through the track's sorting door so a
  /// key dragged past a neighbour cannot break the hold rule. One gesture is
  /// one undo entry: pass the gesture's [mergeKey].
  void nudgeKeys(Duration by, {String? mergeKey}) {
    var refs = selectedKeys.toList();
    if (refs.isEmpty) return;
    perform('Move ${_keyCount(refs)}', mergeKey: mergeKey, () {
      for (var ref in refs) {
        var track = trackOf(ref.motion, ref.group, ref.prop)!;
        var key = keyOf(ref)!;
        var at = key.at + by;
        track.moveKey(key, at < Duration.zero ? Duration.zero : at);
      }
    });
  }

  void deleteKeys() {
    var refs = selectedKeys.toList();
    if (refs.isEmpty) return;
    perform('Delete ${_keyCount(refs)}', () {
      for (var ref in refs) {
        trackOf(ref.motion, ref.group, ref.prop)!.removeKey(keyOf(ref)!);
      }
    });
    clearKeySelection();
  }

  String _keyCount(List<MotionKeyRef> refs) =>
      refs.length == 1 ? '1 key' : '${refs.length} keys';

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
        _openMerge == mergeKey;
    _openMerge = mergeKey;
    if (!merge) {
      _undo.add(
        _JournalEntry(label, doc.snapshot(), _motionSnapshots(), mergeKey),
      );
      if (_undo.length > _journalCap) _undo.removeAt(0);
      _redo.clear();
    }
    doc.edit(mutate);
    _revision++;
    notifyListeners();
  }

  /// The merge key still open, if a gesture is running. Held rather than read
  /// off the last journal entry so that TWO drags of the same property are
  /// two entries: the first ends when [endMerge] is called, and the second
  /// starts fresh even though it carries the same key.
  String? _openMerge;

  /// Close the current merge run — what a gesture calls on release.
  void endMerge() => _openMerge = null;

  void undo() {
    if (_undo.isEmpty) return;
    var entry = _undo.removeLast();
    _redo.add(
      _JournalEntry(entry.label, doc.snapshot(), _motionSnapshots(), null),
    );
    _restore(entry);
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    var entry = _redo.removeLast();
    _undo.add(
      _JournalEntry(entry.label, doc.snapshot(), _motionSnapshots(), null),
    );
    _restore(entry);
    notifyListeners();
  }

  Map<String, MotionSnapshot> _motionSnapshots() => {
    for (var e in motions.entries) e.key: e.value.snapshot(),
  };

  void _restore(_JournalEntry entry) {
    _openMerge = null;
    doc.restore(entry.scene);
    for (var e in entry.motions.entries) {
      motions[e.key]?.restore(e.value);
    }
    _revision++;
  }

  /// Bumped by every door, undo and redo — what a file's dirty flag counts.
  /// Deliberately not content-comparing: undoing back to the saved state
  /// still reads as dirty, which is the safe direction to be wrong in.
  var _revision = 0;

  int get revision => _revision;

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
