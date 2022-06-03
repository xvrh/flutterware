import 'package:flutter/material.dart';

import '../app/project_view.dart';
import '../app/ui/breadcrumb.dart';

class DependenciesScreen extends StatelessWidget {
  const DependenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([
      BreadcrumbItem(Text('Dependencies')),
    ]);
    return Text('Dependencies');
  }
}
