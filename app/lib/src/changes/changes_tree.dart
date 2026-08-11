/// The directory tree of a change set, and the filter it drives.
///
/// **Structure, not navigation.** Clicking a directory narrows the list to it,
/// which is the one thing a tree does that a flat ranked list cannot: answer
/// *what did this touch in `app/lib/src/motion`* without reading forty paths.
/// Selecting a file scrolls to it rather than opening anything.
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

  List<TreeNode> get sortedChildren =>
      children.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  List<FileChange> get sortedFiles =>
      [...files]..sort((a, b) => a.path.compareTo(b.path));
}

/// Folds [files] into a directory tree.
///
/// **Single-child directories are collapsed into their parent** — `app/lib/src`
/// is one row, not three. A repo whose every path starts with the same four
/// segments would otherwise spend the whole rail on prefixes nobody is choosing
/// between.
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

/// Paths matching a typed query — a plain substring, case-insensitive.
///
/// Deliberately not fuzzy. A filter over paths you are *reading* wants to be
/// predictable: `motion` matching `m-o-t-i-o-n` scattered through a path is a
/// result nobody asked for and cannot un-see.
Set<String> pathsMatching(List<FileChange> files, String query) {
  var needle = query.trim().toLowerCase();
  if (needle.isEmpty) return {for (var file in files) file.path};
  return {
    for (var file in files)
      if (file.path.toLowerCase().contains(needle)) file.path,
  };
}
