import 'dart:io';
import 'package:path/path.dart' as p;

// Alternative: git rev-parse --show-toplevel
final String repositoryRoot = (() {
  var directory = Directory.current.absolute;
  while (true) {
    if (directory
        .listSync()
        .whereType<Directory>()
        .any((d) => p.basename(d.path) == '.git')) {
      return directory.path;
    }

    var parent = directory.parent;
    if (parent.path == directory.path) {
      throw Exception("Can't find root directory");
    }

    directory = parent;
  }
})();
