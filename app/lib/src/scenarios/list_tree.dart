import 'package:flutterware/plugins.dart' show fuzzyMatch;
import 'package:path/path.dart' as p;

import 'discovery.dart';

/// One row of the scenario list: a folder, a file, or a scenario.
///
/// Built fresh from the scan result on every change rather than kept in sync,
/// the way the catalog's tree is (`previews/catalog_tree.dart`) — the scan
/// hands over a flat list and the tree is a view of it.
sealed class ScenarioListNode {
  const ScenarioListNode();
}

/// A folder, or the file level below it.
///
/// The file level is **always there**, where the catalog folds a
/// single-entry file away: the file is part of a scenario's address, and it
/// is the only thing telling two same-named scenarios in sibling files apart
/// (see the duplicate rules on [ScenarioScanner]).
class ScenarioBranchNode extends ScenarioListNode {
  ScenarioBranchNode({
    required this.id,
    required this.label,
    required this.file,
    required this.children,
    this.marks = const [],
  });

  /// The project-relative path of the folder or file. Expansion state is
  /// keyed by it, and it deliberately keeps the prefix the labels drop — a
  /// new file changing what the suite shares must not fold anything.
  final String id;

  /// The path segment: a folder's name, or a file's basename.
  final String label;

  /// The declaring file's full path for a file row, null for a folder. The
  /// tooltip shows it, since the label alone no longer says where it is.
  final String? file;

  final List<ScenarioListNode> children;

  /// Which characters of [label] answered the filter.
  final List<int> marks;

  /// Scenarios below, at any depth — what a closed row shows as its count.
  int get scenarioCount {
    var count = 0;
    for (var child in children) {
      switch (child) {
        case ScenarioLeafNode():
          count++;
        case ScenarioBranchNode():
          count += child.scenarioCount;
      }
    }
    return count;
  }
}

class ScenarioLeafNode extends ScenarioListNode {
  const ScenarioLeafNode(this.ref, {this.marks = const []});

  final ScenarioRef ref;

  /// Which characters of the name the filter matched. Empty when the row is
  /// here because a branch above it answered instead.
  final List<int> marks;
}

/// Arranges [scenarios] into folders, files and leaves.
///
/// The directory part of each file becomes the folders, minus the prefix
/// every file shares — a suite kept conventionally under `test/scenarios/`
/// should not make you unfold `test` to see anything. Folders and files sort
/// alphabetically, folders first; a file's scenarios stay in declaration
/// order, which is the order the file's author put them in and the shape the
/// reader knows the suite by.
List<ScenarioListNode> buildScenarioTree(List<ScenarioRef> scenarios) {
  if (scenarios.isEmpty) return const [];
  var common = commonScenarioDirectory([for (var ref in scenarios) ref.file]);
  var skip = common.isEmpty ? 0 : p.url.split(common).length;
  var root = _Builder();
  for (var ref in scenarios) {
    var directory = ref.file.split('/')..removeLast();
    var branch = root;
    var id = StringBuffer();
    for (var (index, segment) in directory.indexed) {
      if (id.isNotEmpty) id.write('/');
      id.write(segment);
      if (index < skip) continue;
      branch = branch.folder(segment, id.toString());
    }
    branch.file(ref.file).add(ScenarioLeafNode(ref));
  }
  return root.build();
}

/// Keeps what matches [query], with the characters that answered marked.
///
/// The same fuzzy matcher that always narrowed this list, applied per node: a
/// scenario's own name keeps its row, and a folder or file whose label
/// answers keeps its whole subtree — typing a file's name is how you ask for
/// its contents, not for the row itself.
List<ScenarioListNode> filterScenarioTree(
  List<ScenarioListNode> nodes,
  String query,
) {
  var needle = query.trim();
  if (needle.isEmpty) return nodes;
  return [for (var node in nodes) ?_filter(node, needle)];
}

ScenarioListNode? _filter(ScenarioListNode node, String needle) {
  switch (node) {
    case ScenarioLeafNode(:var ref):
      var match = fuzzyMatch(needle, ref.name);
      return match == null ? null : ScenarioLeafNode(ref, marks: match.matched);
    case ScenarioBranchNode():
      if (fuzzyMatch(needle, node.label) case var onLabel?) {
        return ScenarioBranchNode(
          id: node.id,
          label: node.label,
          file: node.file,
          children: node.children,
          marks: onLabel.matched,
        );
      }
      var kept = [for (var child in node.children) ?_filter(child, needle)];
      return kept.isEmpty
          ? null
          : ScenarioBranchNode(
              id: node.id,
              label: node.label,
              file: node.file,
              children: kept,
            );
  }
}

/// Keeps the scenarios [keep] answers true for, and the branches leading to
/// them — the "changed on this branch" filter, which composes with the text
/// one.
List<ScenarioListNode> restrictScenarioTree(
  List<ScenarioListNode> nodes,
  bool Function(ScenarioRef ref) keep,
) => [for (var node in nodes) ?_restrict(node, keep)];

ScenarioListNode? _restrict(
  ScenarioListNode node,
  bool Function(ScenarioRef ref) keep,
) {
  switch (node) {
    case ScenarioLeafNode(:var ref):
      return keep(ref) ? node : null;
    case ScenarioBranchNode():
      var kept = [for (var child in node.children) ?_restrict(child, keep)];
      return kept.isEmpty
          ? null
          : ScenarioBranchNode(
              id: node.id,
              label: node.label,
              file: node.file,
              children: kept,
            );
  }
}

/// Every scenario under [node], at any depth — what a folded row is asked
/// about.
Iterable<ScenarioRef> scenarioRefsBelow(ScenarioBranchNode node) sync* {
  for (var child in node.children) {
    switch (child) {
      case ScenarioLeafNode(:var ref):
        yield ref;
      case ScenarioBranchNode():
        yield* scenarioRefsBelow(child);
    }
  }
}

/// Every branch id in the tree, at any depth — what "collapse all" has to
/// name.
Set<String> allScenarioBranches(List<ScenarioListNode> nodes) => {
  for (var node in nodes)
    if (node case ScenarioBranchNode(:var children)) ...[
      node.id,
      ...allScenarioBranches(children),
    ],
};

/// How many rows [nodes] lays out with everything open.
///
/// Folders and files count: a branch is a row like any other, and what the
/// count is compared against is the height of the pane. See
/// `foldsOnArrival`.
int scenarioTreeRows(List<ScenarioListNode> nodes) {
  var rows = 0;
  for (var node in nodes) {
    rows++;
    if (node case ScenarioBranchNode(:var children)) {
      rows += scenarioTreeRows(children);
    }
  }
  return rows;
}

/// The branch ids that have to be open for [file]'s scenarios to be visible:
/// the file itself and every directory above it.
///
/// Computable from the path alone because branch ids *are* paths — no walk,
/// and ids the tree does not contain (the shared prefix's directories) are
/// harmless to open.
Set<String> scenarioBranchesTo(String file) {
  var ids = <String>{file};
  var segments = file.split('/')..removeLast();
  var id = StringBuffer();
  for (var segment in segments) {
    if (id.isNotEmpty) id.write('/');
    id.write(segment);
    ids.add(id.toString());
  }
  return ids;
}

class _Builder {
  final _folders = <String, (String, _Builder)>{};
  final _files = <String, (String, List<ScenarioLeafNode>)>{};

  _Builder folder(String label, String id) =>
      _folders.putIfAbsent(label, () => (id, _Builder())).$2;

  List<ScenarioLeafNode> file(String path) {
    var label = path.split('/').last;
    return _files.putIfAbsent(label, () => (path, [])).$2;
  }

  List<ScenarioListNode> build() => [
    // Folders first, then files, each alphabetical: a folder is a place and
    // a file is a thing, and mixing them makes a list you have to read
    // rather than scan. The leaves under a file keep their declaration
    // order.
    for (var label in _folders.keys.toList()..sort())
      ScenarioBranchNode(
        id: _folders[label]!.$1,
        label: label,
        file: null,
        children: _folders[label]!.$2.build(),
      ),
    for (var label in _files.keys.toList()..sort())
      ScenarioBranchNode(
        id: _files[label]!.$1,
        label: label,
        file: _files[label]!.$1,
        children: _files[label]!.$2,
      ),
  ];
}
