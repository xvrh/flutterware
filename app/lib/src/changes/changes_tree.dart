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
import 'change_set.dart';
import 'patch_index.dart';

export '../utils/string/compare_names.dart' show compareNames;

/// One row under a directory: a file in the patch, or an untracked path.
///
/// Two kinds, one ordering. The alternative — tracked files sorted, then
/// untracked ones after them — is the *sort by a number nobody can see* this
/// file already argued its way out of once: a new file would sit at the bottom
/// of its folder for a reason that is invisible in the row, and browsing is
/// done by name.
sealed class TreeLeaf {
  const TreeLeaf();

  String get path;

  String get name => path.substring(path.lastIndexOf('/') + 1);
}

final class ChangedLeaf extends TreeLeaf {
  const ChangedLeaf(this.file);

  final FileChange file;

  @override
  String get path => file.path;
}

/// An untracked **file**. Never a directory — see [buildTree].
final class UntrackedLeaf extends TreeLeaf {
  const UntrackedLeaf(this.entry);

  final UntrackedEntry entry;

  @override
  String get path => entry.path;
}

/// A directory in the tree, with everything under it already counted.
class TreeNode {
  TreeNode(this.name, this.path);

  /// The last path segment; `·` for the root.
  final String name;

  /// The full directory path, `/`-separated, empty for the root.
  final String path;

  final children = <String, TreeNode>{};
  final leaves = <TreeLeaf>[];

  /// Files anywhere beneath this node, not only directly in it. What the row
  /// shows, because a directory that says `2` while holding forty is worse than
  /// saying nothing.
  ///
  /// Untracked files are in the number, because they are in the tree: a count
  /// that skipped them would be the *quietly wrong count* pins were let into
  /// the tree to avoid, one folder down.
  int get totalFiles =>
      leaves.length + children.values.fold(0, (sum, c) => sum + c.totalFiles);

  /// By name, the way a file explorer lists a directory.
  List<TreeNode> get sortedChildren =>
      children.values.toList()..sort((a, b) => compareNames(a.name, b.name));

  /// The same rule, on the basename — which is what the row draws. A file's
  /// row shows `gone.dart`, never the directory it is already sitting under,
  /// so ordering by the full path would order by something invisible, which is
  /// the mistake this whole file just stopped making.
  List<TreeLeaf> get sortedLeaves =>
      [...leaves]..sort((a, b) => compareNames(a.name, b.name));
}

/// Folds [files] and the untracked *files* in [untracked] into one directory
/// tree.
///
/// **Untracked files belong in the tree; untracked directories do not.** The
/// two are one word in git's output and two different things here, and the
/// whole freeze-guard this screen is built around is about the second: git
/// reports the topmost wholly-untracked *directory* and does not descend, so
/// `build/` is a single entry standing for a subtree nobody has walked, and
/// folding that into a tree would claim a shape that was never read — and draw
/// a folder row that cannot be opened. An untracked *file* has a full path that
/// git handed us, so placing it costs nothing and hides nothing.
///
/// What that buys is the case this screen exists for: an agent's new file is
/// where it lives, beside the files it sits next to, rather than in a drawer at
/// the foot of the list — and whether the agent got as far as `git add` stops
/// deciding how its work is presented. The directories keep their own tail,
/// where their one honest sentence — *not scanned* — has room to be said.
///
/// A directory in [untracked] is dropped here rather than asserted against:
/// `buildUntrackedDirectoryRows` is what draws it, and both read the same list.
///
/// Single-child directories are collapsed into their parent — `app/lib/src` is
/// one row, not three. A repo whose every path starts with the same four
/// segments would otherwise spend the whole rail on prefixes that offer no
/// choice.
TreeNode buildTree(
  List<FileChange> files, {
  List<UntrackedEntry> untracked = const [],
}) {
  var root = TreeNode('·', '');

  void place(String path, TreeLeaf leaf) {
    var parts = path.split('/');
    var node = root;
    for (var i = 0; i < parts.length - 1; i++) {
      var name = parts[i];
      var at = node.path.isEmpty ? name : '${node.path}/$name';
      node = node.children[name] ??= TreeNode(name, at);
    }
    node.leaves.add(leaf);
  }

  for (var file in files) {
    place(file.path, ChangedLeaf(file));
  }
  for (var entry in untracked) {
    if (entry.isDirectory) continue;
    place(entry.path, UntrackedLeaf(entry));
  }

  return _collapse(root);
}

/// Merges a directory that holds exactly one directory and no files of its own
/// into that child, so the label becomes `lib/src/motion`.
TreeNode _collapse(TreeNode node) {
  var collapsed = TreeNode(node.name, node.path)..leaves.addAll(node.leaves);
  for (var child in node.children.values) {
    var folded = _collapse(child);
    while (folded.leaves.isEmpty && folded.children.length == 1) {
      var only = folded.children.values.single;
      folded = TreeNode('${folded.name}/${only.name}', only.path)
        ..leaves.addAll(only.leaves)
        ..children.addAll(only.children);
    }
    collapsed.children[folded.name] = folded;
  }
  return collapsed;
}
