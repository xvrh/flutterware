import 'package:flutter/material.dart';

import '../../../project.dart';

class ProjectScreen extends StatelessWidget {
  final Project project;

  const ProjectScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text(project.directory.path),
    );
  }
}
