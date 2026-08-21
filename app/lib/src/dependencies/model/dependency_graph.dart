/// The chains by which [package] is pulled in, shortest first.
///
/// Walks *up* from [package] through [getDependantPackages] until it reaches
/// something nothing depends on — a root — and returns each chain root-first,
/// ending at [package]:
///
/// ```
/// [[my_app, http, async], [my_app, shelf, async]]
/// ```
///
/// Breadth-first and capped. This used to enumerate every path depth-first
/// and without a bound, which is exponential in a dense graph and was being
/// called from inside a `Tooltip`'s build. Breadth-first means the [limit]
/// chains kept are the shortest ones, which are also the ones worth reading:
/// "you asked for this, which needs that" beats a fourteen-hop tour of the same
/// subgraph.
///
/// A chain never revisits a package, so a dependency cycle terminates instead
/// of spinning.
List<List<String>> shortestDependencyPaths(
  String package,
  Set<String> Function(String) getDependantPackages, {
  int limit = 12,
}) {
  var results = <List<String>>[];
  // Each entry is a chain from `package` upward; reversed on the way out.
  var queue = <List<String>>[
    [package],
  ];
  var head = 0;

  while (head < queue.length && results.length < limit) {
    var path = queue[head++];
    var dependants = getDependantPackages(path.last);

    // Nothing depends on it, so this is where the chain started.
    if (dependants.isEmpty) {
      results.add(path.reversed.toList());
      continue;
    }

    for (var dependant in dependants) {
      if (path.contains(dependant)) continue;
      queue.add([...path, dependant]);
    }
  }

  return results;
}
