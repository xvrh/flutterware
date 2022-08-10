import 'package:flutter/material.dart';
import 'package:flutterware_app/src/project.dart';
import 'package:flutterware_app/src/utils.dart';

import 'board.dart';

class DrawingScreen extends StatelessWidget {
  final Project project;

  const DrawingScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return RouterOutlet({
      'files/:file': (r) => BoardScreen(project.drawing.files.value
          .firstWhere((e) => e.filePath == r['file']))
    });
  }
}
