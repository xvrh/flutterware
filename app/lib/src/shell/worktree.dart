/// One git worktree of the project.
class Worktree {
  const Worktree({
    required this.path,
    this.branch,
    this.head,
    this.isMain = false,
    this.title,
  });

  /// Absolute path to the checkout.
  final String path;

  /// The checked-out branch, or null when the worktree is detached.
  final String? branch;

  /// The commit the worktree is on.
  final String? head;

  /// The repository's primary checkout — the first entry git reports. It cannot
  /// be removed, so teardown must never offer to.
  final bool isMain;

  /// A human label contributed by a plugin (a Claude session title, a PR
  /// title). Null until something better than the branch is known.
  final String? title;

  /// What a tab or switcher row shows, best-first: a contributed title, then
  /// the branch, then the directory name.
  String get displayName {
    if (title != null) return title!;
    if (branch != null) return branch!;
    return path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
  }

  Worktree withTitle(String? title) => Worktree(
    path: path,
    branch: branch,
    head: head,
    isMain: isMain,
    title: title,
  );

  @override
  bool operator ==(Object other) => other is Worktree && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'Worktree(${branch ?? head ?? '?'} @ $path)';
}

/// Parses `git worktree list --porcelain`.
///
/// The porcelain format is a stanza per worktree separated by blank lines:
///
/// ```
/// worktree /path/to/main
/// HEAD 1a2b3c…
/// branch refs/heads/main
///
/// worktree /path/to/other
/// HEAD 4d5e6f…
/// detached
/// ```
///
/// The first stanza is always the main checkout. Unknown attribute lines
/// (`bare`, `locked`, `prunable`) are ignored rather than treated as errors, so
/// a newer git cannot break discovery.
List<Worktree> parseWorktreeList(String output) {
  var worktrees = <Worktree>[];
  String? path;
  String? branch;
  String? head;

  void flush() {
    if (path == null) return;
    worktrees.add(
      Worktree(
        path: path!,
        branch: branch,
        head: head,
        isMain: worktrees.isEmpty,
      ),
    );
    path = null;
    branch = null;
    head = null;
  }

  for (var line in output.split('\n')) {
    line = line.trimRight();
    if (line.isEmpty) {
      flush();
      continue;
    }
    var space = line.indexOf(' ');
    var key = space == -1 ? line : line.substring(0, space);
    var value = space == -1 ? '' : line.substring(space + 1);
    switch (key) {
      case 'worktree':
        flush();
        path = value;
      case 'HEAD':
        head = value;
      case 'branch':
        branch = value.startsWith('refs/heads/')
            ? value.substring('refs/heads/'.length)
            : value;
    }
  }
  flush();
  return worktrees;
}
