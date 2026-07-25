/// One git worktree of the project.
///
/// Discovery (`git worktree list`) lands with the shell; this is the value the
/// rest of the shell and every plugin is handed.
class Worktree {
  const Worktree({required this.path, required this.branch, this.title});

  /// Absolute path to the checkout.
  final String path;

  final String branch;

  /// A human label contributed by a plugin (a Claude session title, a PR
  /// title). Null until something better than the branch is known.
  final String? title;

  /// What the tab and switcher row show, best-first.
  String get displayName => title ?? branch;

  @override
  bool operator ==(Object other) => other is Worktree && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'Worktree($branch @ $path)';
}
