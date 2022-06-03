import 'package:flutter/material.dart';

import '../app/project_view.dart';

class ProjectInfoScreen extends StatelessWidget {
  const ProjectInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([]);
    return Text('''
## Project name
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
''');
  }
}
