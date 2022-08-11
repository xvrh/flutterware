import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/path.dart';
import 'package:flutterware_app/src/drawing/screen_path.dart';
import 'package:flutterware_app/src/project.dart';
import 'package:flutterware_app/src/utils.dart';

import 'model/file.dart';

class DrawingScreen extends StatelessWidget {
  final Project project;

  const DrawingScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return RouterOutlet({
      'files/:file': (r) => ValueListenableBuilder<Iterable<DrawingFile>>(
          valueListenable: project.drawing.files,
          builder: (context, files, child) {
            return _FileScreen(
                project, files.firstWhere((e) => e.filePath == r['file']));
          })
    });
  }
}

class _FileScreen extends StatelessWidget {
  final Project project;
  final DrawingFile file;

  const _FileScreen(this.project, this.file);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet({
      '': (_) => _FileHomeScreen(file),
      ':name': (r) => ValueListenableBuilder<List<DrawingEntry>>(
          valueListenable: file.entries,
          builder: (context, entries, child) {
            return _ComponentScreen(
                project, file, entries.firstWhere((e) => e.name == r['name']));
          }),
    });
  }
}

class _FileHomeScreen extends StatelessWidget {
  final DrawingFile file;

  const _FileHomeScreen(this.file);

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text('''Board ${file.filePath} ${file.toCode()}
      
====
Preview all components in the files:
- Path, Paint etc...


- Button to add a new component
- Context/hamburger menu on each component to delete
      
'''),
    );
  }
}

class _ComponentScreen extends StatelessWidget {
  final Project project;
  final DrawingFile file;
  final DrawingEntry entry;

  const _ComponentScreen(this.project, this.file, this.entry);

  @override
  Widget build(BuildContext context) {
    var entry = this.entry;
    if (entry is DrawingPath) {
      return PathScreen(project, file, entry);
    } else {
      return Text('Unknown ${entry.typeName}');
    }
  }
}
