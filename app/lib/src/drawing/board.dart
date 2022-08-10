

import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/file.dart';
import 'package:flutterware_app/src/utils.dart';

class BoardScreen extends StatelessWidget {
  final DrawingFile file;

  const BoardScreen(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    return RouterOutlet({
      '': (_) => _FileScreen(file),
      ':index': (r) => _ComponentScreen(file, file.entries.value[r.int('index')]),
    });
    // Main interactive panel, clickable on node
    // Right panel with properties:
    //  - component name
    //  - path parts
    //      type | points
    "";

  }
}

class _FileScreen extends StatelessWidget {
  final DrawingFile file;

  const _FileScreen(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(child: Text('Board ${file.filePath} ${file.toCode()}'),);
  }
}

class _ComponentScreen extends StatelessWidget {
  final DrawingFile file;
  final DrawingEntry entry;

  const _ComponentScreen(this.file, this.entry, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(child: Text('Component ${file.filePath} ${entry.name.value}'),);
  }
}