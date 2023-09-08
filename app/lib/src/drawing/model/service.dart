import 'dart:async';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';
import 'package:watcher/watcher.dart';
import '../../project.dart';
import 'file.dart';

final _logger = Logger('drawing_service');

class DrawingService {
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

  void _onFileChange(WatchEvent event) async {
    if (event.path.endsWith(DrawingFile.fileExtension)) {
      if (event.type == ChangeType.ADD) {
        var drawingFile = await _tryReadFile(File(event.path));
        if (drawingFile != null) {
          _files.value = [..._files.value, drawingFile];
          _logger.fine('Added file ${drawingFile.filePath}');
        }
      } else if (event.type == ChangeType.MODIFY) {
        var drawingFile = await _tryReadFile(File(event.path));
        if (drawingFile != null) {
          var existingFile = _files.value
              .firstWhereOrNull((e) => e.filePath == drawingFile.filePath);
          if (existingFile != null &&
              existingFile.toCode() != drawingFile.toCode()) {
            var newFiles = _files.value.toList();
            newFiles[newFiles.indexOf(existingFile)] = drawingFile;
            _files.value = newFiles;
            existingFile.dispose();

            _logger.fine('Updated file ${drawingFile.filePath}');
          }
        }
      } else if (event.type == ChangeType.REMOVE) {
        var filePath = p.relative(File(event.path).absolute.path,
            from: project.absolutePath);
        var existingFile =
            _files.value.firstWhereOrNull((e) => e.filePath == filePath);
        if (existingFile != null) {
          var newFiles = _files.value.toList()..remove(existingFile);
          _files.value = newFiles;
          existingFile.dispose();
          _logger.fine('Remove file $filePath');
        }
      }
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

    await for (var dir in project.directory.list()) {
      var basedir = p.basename(dir.path);
      if (dir is Directory &&
          !const ['.dart_tool', 'build', 'out'].contains(basedir)) {
        await for (var file in dir
            .list(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith(DrawingFile.fileExtension))) {
          await tryAdd(file);
        }
      } else if (dir is File && dir.path.endsWith(DrawingFile.fileExtension)) {
        await tryAdd(dir);
      }
    }
    return results;
  }

  Future<DrawingFile?> _tryReadFile(File file) async {
    var content = await file.readAsString();
    if (content.contains(DrawingFile.fileTag)) {
      try {
        var filePath =
            p.relative(file.absolute.path, from: project.absolutePath);
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
