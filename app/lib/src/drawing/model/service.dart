import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/file.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import '../../project.dart';

final _logger = Logger('drawing_service');

class DrawingService {
  static const _fileSuffix = '.gen.dart';

  final Project project;
  final _files = ValueNotifier<List<DrawingFile>>([]);
  StreamSubscription? _watcherSubscription;

  DrawingService(this.project);

  void ensureStarted() async {
    var initialFiles = await _listAllFiles();
    _files.value = initialFiles;

    _watcherSubscription =
        DirectoryWatcher(project.directory.path).events.listen(_onFileChange);
  }

  void _onFileChange(WatchEvent event)  async {
    print("${event.path} ${event.type}");
    if (event.path.endsWith(_fileSuffix)) {
      if (event.type == ChangeType.ADD) {
        var drawingFile = await _tryReadFile(File(event.path));
        if (drawingFile != null) {
          _files.value = [..._files.value, drawingFile];
        }
      }
      // remove (+ dispose), add, update (only if content != from last content written)?
    }
  }

  Future<List<DrawingFile>> _listAllFiles() async {
    var results = <DrawingFile>[];
    Future<void> tryAdd(File file) async {
      var drawingFile = await _tryReadFile(file);
      if (drawingFile != null) {
        results.add(drawingFile);
      }
    }

    await for (var dir in  project.directory.list()) {
      var basedir = p.basename(dir.path);
      if (dir is Directory && !const ['.dart_tool', 'build', 'out'].contains(basedir)) {
        await for (var file in  dir.list(recursive: true).whereType<File>().where((f) => f.path.endsWith(_fileSuffix))) {
          await tryAdd(file);
        }
      } else if (dir is File && dir.path.endsWith(_fileSuffix)) {
        await tryAdd(dir);
      }
    }
    return results;
  }

  Future<DrawingFile?> _tryReadFile(File file) async {
    var content = await file.readAsString();
    if (content.contains(DrawingFile.fileTag)) {
      try {
        var filePath = p.relative(file.absolute.path, from: project.absolutePath);
        return DrawingFile.parse(filePath, content);
      } catch (e, s) {
        _logger.warning('Failed to load file ${file.path}', e, s);
      }
    }
    return null;
  }

  ValueListenable<Iterable<DrawingFile>> get files => _files;

  // Expose ValueListener with the list of files
  // Listen watcher for file change
  // Apply changes from file system (incremental and disposable)
  // All files are ergely loaded (after first launch)

  void dispose() {
    _watcherSubscription?.cancel();
    for (var file in _files.value) {
      file.dispose();
    }
    _files.dispose();
  }
}
