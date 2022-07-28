List<List<String>> dependenciesGraph(
    String package, Set<String> Function(String) getDependantPackages,
    {Set<String>? visited}) {
  if (visited != null && visited.contains(package)) {
    return [];
  }

  var dependants = getDependantPackages(package);
  if (dependants.isEmpty) {
    return [
      [package]
    ];
  }

  var lists = <List<String>>[];
  for (var dependant in dependants) {
    var subPaths = dependenciesGraph(dependant, getDependantPackages,
        visited: {package, ...?visited});
    for (var subPath in subPaths) {
      lists.add([...subPath, package]);
    }
  }
  return lists;
}
