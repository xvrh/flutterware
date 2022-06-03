import 'package:flutter/material.dart';

import '../app/project_view.dart';

class TestRunnerScreen extends StatelessWidget {
  const TestRunnerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([
      BreadcrumbItem(Text('App tests')),
    ]);
    return Text('''Explain app test feature
Link to doc
Button "add a test"
Screenshot of expected workflow    
    
''');
  }
}
