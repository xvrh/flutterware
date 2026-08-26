/// The directory tree of a change set.
///
/// Structure, which a ranked list cannot carry. A flat list of fifty-three
/// filenames answers "what should I look at" and says nothing at all about the
/// shape of the branch — that 27 of them are under `app/lib`, that `docs` was
/// touched once. It was dropped in the master/detail rewrite and put back the
/// same day, because that was the wrong thing to have taken away.
///
/// Ordered by name. It was ordered by weight, so that the directory an agent
/// hammered sorted to the top and inside it so did the file, and the argument
/// for that was that you do not know the name you want. In use the argument
/// failed for a plainer reason: **the row sorts by a number it does not show**.
/// A folder row prints its file count, so a real branch came out 59, 60, 6, 3,
/// 4, 5 down the rail and read as no order at all — `lib` above `app` because
/// it churned more, `docs` above `doc`. An order nobody can see is worse than
/// one nobody needs, and the ranking already has a surface of its own: the
/// *Important* tab, which is where "what first" is answered. *All* is where you
/// navigate, and navigating is done by name.
///
/// Case-insensitively, with the case-sensitive comparison as the tiebreak, so
/// `README.md` sits among its neighbours instead of above every lowercase path
/// and two spellings never swap places between rebuilds.
///
/// The model is pure Dart so the folding — the part with the off-by-one in
/// it — is testable without pumping.
library;

import '../utils/string/compare_names.dart';
import 'patch_index.dart';

export '../utils/string/compare_names.dart' show compareNames;

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

  /// By name, the way a file explorer lists a directory.
  List<TreeNode> get sortedChildren =>
      children.values.toList()..sort((a, b) => compareNames(a.name, b.name));

  /// The same rule, on the basename — which is what the row draws. A file's
  /// row shows `gone.dart`, never the directory it is already sitting under,
  /// so ordering by the full path would order by something invisible, which is
  /// the mistake this whole file just stopped making.
  List<FileChange> get sortedFiles =>
      [...files]
        ..sort((a, b) => compareNames(_basename(a.path), _basename(b.path)));

  static String _basename(String path) =>
      path.substring(path.lastIndexOf('/') + 1);
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
