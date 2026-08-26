/// The directory tree of a bundle.
///
/// Structure and weight, which a flat list cannot carry. A list of two hundred
/// filenames answers "is `logo.png` in there" and says nothing about the shape
/// of the bundle — that `assets/images` is 4 MB of it, that `assets/i18n`
/// holds forty files nobody has looked at since. The list already admits the
/// hierarchy by printing a directory under every row; this is the same
/// information arranged so it can be counted.
///
/// Grown from asset **keys**, never from the paths on disk. A key is what
/// `Image.asset` is given, and it never names a density directory: the `2.0x/`
/// beside a PNG is spliced into the variant's own [AssetFile.key] and appears
/// nowhere else. A tree grown from keys therefore cannot sprout a `2.0x` folder
/// that is not in the bundle, and one grown from file paths grows one under
/// every directory that has variants.
///
/// Pure Dart, like the changes tree it borrows its folding from, so the part
/// with the off-by-one in it is testable without pumping a widget.
library;

import '../../utils/string/compare_names.dart';
import 'asset_catalog.dart';

/// A directory of the bundle, with everything beneath it already counted.
class AssetNode {
  AssetNode(this.name, this.path);

  /// What the row shows. More than one segment after a collapse:
  /// `illustrations/onboarding`.
  final String name;

  /// The full key prefix this node stands for. Two directories with the same
  /// name under different parents are different rows, and this is what tells
  /// them apart — including across sections, so a dependency's `assets/images`
  /// and the package's own are never the same expansion.
  final String path;

  final children = <String, AssetNode>{};

  /// The assets directly in this directory.
  final assets = <ResolvedAsset>[];

  /// Assets anywhere beneath, not only directly in. What the row shows,
  /// because a directory that says `2` while holding forty is worse than
  /// saying nothing.
  late final int totalCount =
      assets.length + children.values.fold(0, (sum, c) => sum + c.totalCount);

  /// Every byte beneath, variants included — [ResolvedAsset.totalBytes] already
  /// counts those, and they are as real in the bundle as the 1× file.
  late final int totalBytes =
      assets.fold(0, (sum, a) => sum + a.totalBytes) +
      children.values.fold(0, (sum, c) => sum + c.totalBytes);

  /// Every directory beneath this one, itself excluded — what "collapse all"
  /// has to name, since folding is keyed on [path] and a set of them is the
  /// whole of the state.
  Iterable<String> get descendantPaths sync* {
    for (var child in children.values) {
      yield child.path;
      yield* child.descendantPaths;
    }
  }

  /// By name, never by weight — the same order the changes tree settled on and
  /// for the same reason: **the row prints a number it does not sort by**. A
  /// directory row shows its count and its bytes, so ranking the rows by churn
  /// or by size puts them in an order the reader cannot see, and a list that
  /// reorders itself whenever a PNG is recompressed is a list nobody can learn.
  late final List<AssetNode> sortedChildren = children.values.toList()
    ..sort((a, b) => compareNames(a.name, b.name));

  /// The same rule, on the basename — which is what the row draws. Every asset
  /// in this node shares a directory, so the key would sort the same way today;
  /// it is the basename because that is the thing on screen, and a node that
  /// stopped sharing one would otherwise start ordering by something invisible.
  late final List<ResolvedAsset> sortedAssets = [...assets]
    ..sort((a, b) => compareNames(_basename(a.key), _basename(b.key)));

  static String _basename(String key) =>
      key.substring(key.lastIndexOf('/') + 1);
}

/// One section's keys, folded.
class AssetTree {
  AssetTree._({required this.root, required this.prefix});

  factory AssetTree.of(List<ResolvedAsset> assets) {
    var root = AssetNode('', '');
    for (var asset in assets) {
      // Manifest keys are `/`-separated on every platform — they are not paths
      // on this machine, so `p.split` would be wrong on Windows.
      var parts = asset.key.split('/');
      var node = root;
      for (var i = 0; i < parts.length - 1; i++) {
        var name = parts[i];
        var path = node.path.isEmpty ? name : '${node.path}/$name';
        node = node.children[name] ??= AssetNode(name, path);
      }
      node.assets.add(asset);
    }

    var top = _collapse(root);
    var prefix = <String>[];
    while (top.assets.isEmpty && top.children.length == 1) {
      var only = top.children.values.single;
      prefix.add(only.name);
      top = only;
    }
    return AssetTree._(root: top, prefix: prefix.join('/'));
  }

  /// The directory every row hangs under. Its own row is not drawn: the section
  /// header is already a row, so spending a second one — and a level of
  /// indentation on every asset beneath it — on a prefix that offers no choice
  /// is precisely the waste the tree was meant to end. `assets` for most
  /// projects, `packages/<name>/assets` for a dependency's section.
  final AssetNode root;

  /// What was folded off the top, for a header to say. Empty when the keys
  /// share nothing.
  final String prefix;

  bool get isEmpty => root.children.isEmpty && root.assets.isEmpty;

  /// The directory this path names, or null when nothing here is called that.
  ///
  /// Matched on [AssetNode.path] rather than walked segment by segment,
  /// because the collapse means a node's name is not one segment: the row
  /// labelled `illustrations/onboarding` is reachable by that whole path and by
  /// neither half of it. What an address can carry is what a row can be, and
  /// the row is what is being looked up.
  AssetNode? nodeAt(String path) => _find(root, path);

  static AssetNode? _find(AssetNode node, String path) {
    if (node.path == path) return node;
    // Only down the branch that could hold it — a bundle has a few thousand
    // keys and this runs whenever the address names a directory.
    if (!path.startsWith('${node.path}/') && node.path.isNotEmpty) return null;
    for (var child in node.children.values) {
      if (_find(child, path) case var found?) return found;
    }
    return null;
  }
}

/// Merges a directory holding exactly one directory and no assets of its own
/// into that child, so four levels of `illustrations/onboarding/hero/large`
/// become one row.
///
/// Without it a project whose every key starts with the same three segments
/// spends the whole panel on prefixes that offer no choice.
AssetNode _collapse(AssetNode node) {
  var collapsed = AssetNode(node.name, node.path)..assets.addAll(node.assets);
  for (var child in node.children.values) {
    var folded = _collapse(child);
    while (folded.assets.isEmpty && folded.children.length == 1) {
      var only = folded.children.values.single;
      folded = AssetNode('${folded.name}/${only.name}', only.path)
        ..assets.addAll(only.assets)
        ..children.addAll(only.children);
    }
    collapsed.children[folded.name] = folded;
  }
  return collapsed;
}

/// One heading's worth of a folder sheet: a path, and the assets directly in
/// it.
class AssetSheetSection {
  AssetSheetSection({
    required this.label,
    required this.path,
    required this.assets,
  });

  /// The directory relative to the sheet's own scope. Empty for the assets
  /// sitting directly in the scope, which get no heading.
  final String label;

  /// The full key prefix, for a heading that is also a way in.
  final String path;

  final List<ResolvedAsset> assets;
}

/// [root] flattened into headed sections — every asset beneath it, not only
/// the ones directly in it.
///
/// **A sheet shows what is in the folder, all of it.** A grid of subfolder
/// tiles you have to click through is the tree again, drawn larger and with
/// fewer affordances; the point of a sheet is that a directory of forty
/// pictures is forty pictures on one page. The catalog settled this first and
/// its landing does the same thing.
///
/// The sheet does not nest: a heading is the whole path down to the assets
/// under it — `images/illustrations` rather than an indented `illustrations`
/// inside an `images` — because a grid has no indentation to nest *with*.
///
/// Emitted in the order the tree draws: each directory before the directories
/// inside it, and the loose assets last under no heading. That is the one
/// deliberate difference from the catalog's own walk, which emits a branch
/// after the branches nested in it — here the tree beside the sheet reads top
/// down, and a sheet that did not would be a second order to hold in mind.
List<AssetSheetSection> assetSheetSections(AssetNode root) {
  var sections = <AssetSheetSection>[];

  void walk(AssetNode node, String label) {
    if (label.isNotEmpty && node.assets.isNotEmpty) {
      sections.add(
        AssetSheetSection(
          label: label,
          path: node.path,
          assets: node.sortedAssets,
        ),
      );
    }
    for (var child in node.sortedChildren) {
      walk(child, label.isEmpty ? child.name : '$label/${child.name}');
    }
  }

  walk(root, '');
  if (root.assets.isNotEmpty) {
    sections.add(
      AssetSheetSection(label: '', path: root.path, assets: root.sortedAssets),
    );
  }
  return sections;
}
