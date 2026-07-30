/// One git worktree of the project.
class Worktree {
  const Worktree({
    required this.path,
    this.gitName,
    this.branch,
    this.head,
    this.isMain = false,
    this.title,
  });

  /// What the main checkout is called in an [Address].
  ///
  /// It has no admin directory to be named by, and no ordinary token is safe:
  /// git will happily give a *linked* worktree the admin name `main`, so any
  /// word we reserved could collide with a real one. `~` cannot — git sanitises
  /// admin names into valid refname components and `~` is a refname operator
  /// (see [gitName]). It reads as "home", which is what it means, and RFC 3986
  /// lists it unreserved, so it needs no encoding.
  static const mainName = '~';

  /// Absolute path to the checkout.
  final String path;

  /// Git's own name for this worktree — its directory under `.git/worktrees/`.
  ///
  /// Null for the main checkout, which has none, and when the pointer file
  /// could not be read.
  final String? gitName;

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

  /// The checkout's directory name. What a human sees when nothing better is
  /// known — not an identity, since two worktrees of one repo may share it.
  String get directoryName =>
      path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;

  /// This worktree's identity in an [Address].
  ///
  /// [gitName], because it is the only name git actually keeps unique: it
  /// de-duplicates by suffix (`feature`, `feature1`) even where `--force`
  /// defeated its own checks, and it survives `git worktree move`, which the
  /// directory name does not.
  ///
  /// Deliberately not [displayName]. A title is whatever a plugin last said. A
  /// branch is more *meaningful* — and cannot be an identity, because a
  /// worktree outlives its branch (`git checkout`), a branch moves between
  /// worktrees, and a detached worktree has none. A branch is accepted when
  /// *resolving* an address instead; see `ShellController.worktreeNamed`.
  ///
  /// Falls back to [directoryName] only when the pointer file was unreadable,
  /// which is the best guess available and what git derives the admin name
  /// from anyway.
  String get name => isMain ? mainName : (gitName ?? directoryName);

  /// What a tab or switcher row shows, best-first: a contributed title, then
  /// the branch, then the directory name.
  ///
  /// The directory rather than [name]: the main checkout's identity is `~`,
  /// which is right in an address and useless on a tab.
  String get displayName {
    if (title != null) return title!;
    if (branch != null) return branch!;
    return directoryName;
  }

  Worktree withTitle(String? title) => Worktree(
    path: path,
    gitName: gitName,
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
