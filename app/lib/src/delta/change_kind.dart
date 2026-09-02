/// How a branch touched an entry. Declared in the order the tree ranks them:
/// a new entry outranks an edited one, which outranks one merely reached.
enum EntryChangeKind {
  /// The declaring file is new to git, or every line of the declaration is.
  added,

  /// An edit lands inside the declaration.
  edited,

  /// Nothing in the declaration moved, but something it imports did.
  ///
  /// The weak signal: a shared widget changing reaches most of a catalog, so
  /// `EntryChanges` withholds it past a share of the tree.
  reached,
}
