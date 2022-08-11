

import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/file.dart';
import 'package:flutterware_app/src/drawing/model/path.dart';

import '../project.dart';

class PathScreen extends StatelessWidget {
  final Project project;
  final DrawingFile file;
  final PathElement path;

  const PathScreen(this.project,this.file, this.path,{super.key});

  @override
  Widget build(BuildContext context) {
    return Container(child: Text('Path ${path.id}'),);
  }
}
