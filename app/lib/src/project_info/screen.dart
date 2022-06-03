import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../app/project_view.dart';
import '../project.dart';
import '../utils/data_loader.dart';

class ProjectInfoScreen extends StatelessWidget {
  final Project project;

  const ProjectInfoScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([]);
    return ValueListenableBuilder<Snapshot<Pubspec>>(
      valueListenable: project.pubspec,
      builder: (context, snapshot, child) {
        return Padding(
          padding: const EdgeInsets.all(15),
          child: MarkdownBody(data:'''
## ${snapshot.data?.name ?? ''}
   Path
   Icon (clickable to feature)
   
150 dependencies (12 direct) (link to dependency feature)
          
## Metrics (LoC)
  lib: xx files, 200 LoC
  tests: xx files 
  tool:
  bin:
  example:    
  total: xx, xx
'''),
        );
      }
    );
  }
}
