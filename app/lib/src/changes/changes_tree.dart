/// The directory tree of a change set.
///
/// Structure, which a ranked list cannot carry. A flat list of fifty-three
/// filenames answers "what should I look at" and says nothing at all about the
/// shape of the branch — that 27 of them are under `app/lib`, that `docs` was
/// touched once. It was dropped in the master/detail rewrite and put back the
/// same day, because that was the wrong thing to have taken away.
///
/// Ordered by weight, not by name. This is the one change from the version
/// that was deleted, and it is what lets the tree carry the ranking instead of
/// fighting it: the directory an agent hammered sorts to the top, and inside it
/// so does the file. Alphabetical is the right default for a file explorer,
/// where you know the name you want; here you do not, which is the whole reason
/// the screen exists.
///
/// The model is pure Dart so the folding — the part with the off-by-one in
/// it — is testable without pumping.
library;

import 'patch_index.dart';

/// A directory in the tree, with everything under it already counted.
class TreeNode {
  TreeNode(this.name, this.path);

  /// The last path segment; `·` for the root.
  final String name;

  /// The full directory path, `/`-separated, empty for the root.
  final String path;

  final children = <String, TreeNode>{};
  final files = <FileChange>[];

  /// Files anywhere beneath this node, not only directly in it. What the row
  /// shows, because a directory that says `2` while holding forty is worse than
  /// saying nothing.
  int get totalFiles =>
      files.length + children.values.fold(0, (sum, c) => sum + c.totalFiles);

  int get added =>
      files.fold(0, (sum, f) => sum + f.added) +
      children.values.fold(0, (sum, c) => sum + c.added);

  int get removed =>
      files.fold(0, (sum, f) => sum + f.removed) +
      children.values.fold(0, (sum, c) => sum + c.removed);

  int get lines => added + removed;

  /// Heaviest first, ties broken by name so the order is stable when two
  /// directories have identical weight — which is common at zero.
  List<TreeNode> get sortedChildren => children.values.toList()
    ..sort((a, b) {
      var byWeight = b.lines.compareTo(a.lines);
      return byWeight != 0 ? byWeight : a.name.compareTo(b.name);
    });

  /// Same rule, plus the one the flat list already used: **deletions promoted**,
  /// because `D −88` is the line most worth seeing and a plain churn sort
  /// buries it under three larger edits.
  List<FileChange> get sortedFiles => [...files]
    ..sort((a, b) {
      var byKind = _deletionRank(b.status).compareTo(_deletionRank(a.status));
      if (byKind != 0) return byKind;
      var byWeight = b.lines.compareTo(a.lines);
      return byWeight != 0 ? byWeight : a.path.compareTo(b.path);
    });

  static int _deletionRank(ChangeStatus status) =>
      status == ChangeStatus.deleted ? 1 : 0;
}

/// Folds [files] into a directory tree.
///
/// Single-child directories are collapsed into their parent — `app/lib/src` is
/// one row, not three. A repo whose every path starts with the same four
/// segments would otherwise spend the whole rail on prefixes that offer no
/// choice.
TreeNode buildTree(List<FileChange> files) {
  var root = TreeNode('·', '');

  for (var file in files) {
    var parts = file.path.split('/');
    var node = root;
    for (var i = 0; i < parts.length - 1; i++) {
      var name = parts[i];
      var path = node.path.isEmpty ? name : '${node.path}/$name';
      node = node.children[name] ??= TreeNode(name, path);
    }
    node.files.add(file);
  }

  return _collapse(root);
}

/// Merges a directory that holds exactly one directory and no files of its own
/// into that child, so the label becomes `lib/src/motion`.
TreeNode _collapse(TreeNode node) {
  var collapsed = TreeNode(node.name, node.path)..files.addAll(node.files);
  for (var child in node.children.values) {
    var folded = _collapse(child);
    while (folded.files.isEmpty && folded.children.length == 1) {
      var only = folded.children.values.single;
      folded = TreeNode('${folded.name}/${only.name}', only.path)
        ..files.addAll(only.files)
        ..children.addAll(only.children);
    }
    collapsed.children[folded.name] = folded;
  }
  return collapsed;
}

/// Every path under [directory], for the filter a tree click applies.
///
/// An empty [directory] is the root and matches everything, which is what makes
/// "clear the selection" the same code path as selecting.
Set<String> pathsUnder(List<FileChange> files, String directory) {
  if (directory.isEmpty) return {for (var file in files) file.path};
  var prefix = '$directory/';
  return {
    for (var file in files)
      if (file.path.startsWith(prefix)) file.path,
  };
}
