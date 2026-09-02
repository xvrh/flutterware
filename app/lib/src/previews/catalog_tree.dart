import 'catalog_entry.dart';

/// One row of the entry tree: a folder, a group, or an entry.
///
/// Built fresh from the entry list on every change rather than kept in sync —
/// discovery hands over a flat, sorted list, and the tree is a view of it.
sealed class CatalogNode {
  const CatalogNode();

  /// Stable across rebuilds, because expansion state is keyed by it.
  String get id;
  String get label;
}

/// A folder, or a file's group of variants. Both behave identically: a label
/// you can fold away.
class CatalogBranch extends CatalogNode {
  CatalogBranch({
    required this.id,
    required this.label,
    required this.children,
  });

  @override
  final String id;
  @override
  final String label;

  final List<CatalogNode> children;

  /// The path prefix this branch covers — what selecting it narrows the
  /// catalog to.
  ///
  /// A *path*, not this branch's id, because that is what an address can carry:
  /// a branch id is a chain of labels, half of them from `@Preview(group:)`,
  /// and putting those in the address would be a second namespace in the slot
  /// entry ids already use. See `CatalogPlace`.
  ///
  /// A directory branch covers its directory; a group branch covers the file
  /// its variants are declared in. Which leaves one blunt edge, and it is the
  /// right one to be blunt on: a `group:` shared across two files covers the
  /// directory holding both, so selecting it shows their neighbours too. Groups
  /// are per-file in every catalog seen so far — discovery derives one whenever
  /// a file holds more than one entry — and the alternative is an address that
  /// cannot be written down.
  late final String scopePath = _commonPath(entries);

  /// Entries below this branch, at any depth.
  Iterable<CatalogEntry> get entries sync* {
    for (var child in children) {
      switch (child) {
        case CatalogLeaf(:var entry):
          yield entry;
        case CatalogBranch():
          yield* child.entries;
      }
    }
  }
}

class CatalogLeaf extends CatalogNode {
  const CatalogLeaf(this.entry);

  final CatalogEntry entry;

  @override
  String get id => entry.id;
  @override
  String get label => entry.name;
}

/// Arranges [entries] into folders, groups and leaves.
///
/// The directory part of each path becomes the folders, and a file's [
/// CatalogEntry.group] — which discovery derives whenever a file holds more
/// than one entry — becomes a level below it. The directories every entry
/// shares are dropped: a catalog scanned under `demo/` should not make you
/// unfold `demo` to see anything.
List<CatalogNode> buildCatalogTree(List<CatalogEntry> entries) {
  if (entries.isEmpty) return const [];
  var prefix = _commonDirectory(entries);
  var root = _Builder('');
  for (var entry in entries) {
    var directory = _directorySegments(entry.path).skip(prefix).toList();
    var branch = root;
    for (var segment in directory) {
      branch = branch.child(segment);
    }
    if (entry.group case var group?) branch = branch.child(group);
    branch.leaves.add(CatalogLeaf(entry));
  }
  return root.build();
}

/// What the tree calls [scope] — the heading a narrowed sheet needs, or null
/// for the whole index.
///
/// [buildCatalogTree] drops the directories every entry shares, which for a
/// narrowed catalog is the folder you are standing in: scope a sheet to
/// `demo/team` and the tree it is built from is the *contents* of `team`, with
/// nothing left in it that says so. The page then opened on a row of tiles
/// under no heading and hard against the top of the pane — and only sometimes,
/// because a folder whose entries carry a `group:` keeps that branch and got
/// its heading from it. One folder named, the next one not.
///
/// The name is the scope's last segment, which is exactly what the branch row
/// you clicked is labelled with: a directory branch is named for its directory,
/// and a group branch's own leaves never reach the heading this feeds — every
/// entry in a file that holds more than one has a group, derived if not
/// declared, so they sit under that group's branch rather than loose.
String? scopeHeading(String? scope) => scope?.split('/').last;

/// The branches you would have to open to see [entryId].
///
/// A selection is not always made in the tree — the daemon can move you off an
/// entry it can no longer build, and a screenshot or an index will one day ask
/// for one by id. Whatever is selected has to be visible, whatever was folded
/// away before.
Set<String> branchesTo(List<CatalogNode> nodes, String? entryId) {
  if (entryId == null) return const {};
  var path = <String>{};
  bool search(List<CatalogNode> nodes) {
    for (var node in nodes) {
      switch (node) {
        case CatalogLeaf():
          if (node.id == entryId) return true;
        case CatalogBranch(:var children):
          if (search(children)) {
            path.add(node.id);
            return true;
          }
      }
    }
    return false;
  }

  return search(nodes) ? path : const {};
}

/// Every branch in the tree, at any depth — what "collapse all" has to name.
Set<String> allBranches(List<CatalogNode> nodes) => {
  for (var node in nodes)
    if (node case CatalogBranch(:var children)) ...[
      node.id,
      ...allBranches(children),
    ],
};

/// How many rows [nodes] lays out with everything open.
///
/// Folders and groups count: a branch is a row like any other, and what the
/// count is compared against is the height of the pane. See
/// `foldsOnArrival`.
int catalogTreeRows(List<CatalogNode> nodes) {
  var rows = 0;
  for (var node in nodes) {
    rows++;
    if (node case CatalogBranch(:var children)) {
      rows += catalogTreeRows(children);
    }
  }
  return rows;
}

/// Keeps what matches [query], and the folders leading to it.
///
/// A branch whose own label matches keeps its whole subtree — typing a folder
/// name is how you ask for its contents, not for the folder itself.
List<CatalogNode> filterCatalogTree(List<CatalogNode> nodes, String query) {
  var needle = query.trim().toLowerCase();
  if (needle.isEmpty) return nodes;
  return [for (var node in nodes) ?_filter(node, needle)];
}

CatalogNode? _filter(CatalogNode node, String needle) {
  switch (node) {
    case CatalogLeaf(:var entry):
      return _matches(entry, needle) ? node : null;
    case CatalogBranch(:var children):
      if (node.label.toLowerCase().contains(needle)) return node;
      var kept = [for (var child in children) ?_filter(child, needle)];
      return kept.isEmpty
          ? null
          : CatalogBranch(id: node.id, label: node.label, children: kept);
  }
}

/// Keeps the entries whose id is in [ids], and the folders leading to them —
/// the "changed on this branch" filter, which composes with the text one.
List<CatalogNode> restrictCatalogTree(
  List<CatalogNode> nodes,
  Set<String> ids,
) => [for (var node in nodes) ?_restrict(node, ids)];

CatalogNode? _restrict(CatalogNode node, Set<String> ids) {
  switch (node) {
    case CatalogLeaf(:var entry):
      return ids.contains(entry.id) ? node : null;
    case CatalogBranch(:var children):
      var kept = [for (var child in children) ?_restrict(child, ids)];
      return kept.isEmpty
          ? null
          : CatalogBranch(id: node.id, label: node.label, children: kept);
  }
}

/// Matched against everything that identifies an entry, not only its name: the
/// file is often what you remember, and the symbol is what an agent is told.
bool _matches(CatalogEntry entry, String needle) =>
    entry.name.toLowerCase().contains(needle) ||
    entry.symbol.toLowerCase().contains(needle) ||
    entry.path.toLowerCase().contains(needle) ||
    (entry.group?.toLowerCase().contains(needle) ?? false);

/// How many leading directory segments every entry shares.
int _commonDirectory(List<CatalogEntry> entries) {
  var shared = _directorySegments(entries.first.path);
  for (var entry in entries.skip(1)) {
    var segments = _directorySegments(entry.path);
    var common = 0;
    while (common < shared.length &&
        common < segments.length &&
        shared[common] == segments[common]) {
      common++;
    }
    shared = shared.sublist(0, common);
    if (shared.isEmpty) break;
  }
  return shared.length;
}

/// Always `/`-separated: [CatalogEntry.path] is a project-relative path the
/// daemon wrote, not a host path to be split by the local separator.
List<String> _directorySegments(String path) {
  var segments = path.split('/');
  return segments.sublist(0, segments.length - 1);
}

class _Builder {
  _Builder(this.id);

  final String id;
  final _children = <String, _Builder>{};
  final leaves = <CatalogLeaf>[];

  _Builder child(String label) =>
      _children.putIfAbsent(label, () => _Builder('$id/$label'));

  List<CatalogNode> build() => [
    // Folders first, then entries, each alphabetical: a folder is a place and
    // an entry is a thing, and mixing them makes a list you have to read
    // rather than scan.
    for (var label in _children.keys.toList()..sort())
      CatalogBranch(
        id: _children[label]!.id,
        label: label,
        children: _children[label]!.build(),
      ),
    ...leaves..sort((a, b) => a.label.compareTo(b.label)),
  ];
}

/// The longest path every one of [entries] is inside.
///
/// Segment-wise rather than character-wise, so `demo/team` and `demo/teamwork`
/// have `demo` in common and not `demo/team`.
String _commonPath(Iterable<CatalogEntry> entries) {
  List<String>? common;
  for (var entry in entries) {
    var segments = entry.path.split('/');
    if (common == null) {
      common = segments;
      continue;
    }
    var shared = 0;
    while (shared < common.length &&
        shared < segments.length &&
        common[shared] == segments[shared]) {
      shared++;
    }
    common = common.take(shared).toList();
  }
  return common?.join('/') ?? '';
}
