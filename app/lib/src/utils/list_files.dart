import 'dart:io';
import 'package:path/path.dart' as p;
import 'ignore.dart';

Iterable<File> listFilesInDirectory(String root) {
  return _Directory(root).list();
}

class _Directory {
  final _Directory? parent;
  final String directoryPath;
  Ignore? _ignore;

  _Directory(this.directoryPath, {this.parent}) {
    var gitignore = File(p.join(directoryPath, '.gitignore'));
    if (gitignore.existsSync()) {
      _ignore = Ignore([gitignore.readAsStringSync()]);
    }
  }

  String get rootPath => parent?.rootPath ?? directoryPath;

  Iterable<File> list() sync* {
    var files = Directory(directoryPath).listSync();
    for (var file in files) {
      if (file is File) {
        if (!_ignores(file.path)) {
          yield file;
        }
      } else if (file is Directory) {
        if (!_ignores('${file.path}/')) {
          var subDirectory = _Directory(file.path, parent: this);
          yield* subDirectory.list();
        }
      }
    }
  }

  bool _ignores(String path) {
    var ignored = false;
    if (_ignore != null) {
      var relativePath = p.relative(path, from: directoryPath);
      ignored |= _ignore!.ignores(relativePath);
    }
    if (parent != null) {
      ignored |= parent!._ignores(path);
    }
    return ignored;
  }
}
