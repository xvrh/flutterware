import 'package:flutter/material.dart';

import '../project.dart';

class IconScreen extends StatelessWidget {
  final Project project;

  const IconScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text('Icon');
  }
}
