import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../app/project_view.dart';
import '../app/ui/breadcrumb.dart';

class DependenciesScreen extends StatelessWidget {
  const DependenciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([
      BreadcrumbItem(Text('Dependencies')),
    ]);
    return Padding(
      padding: const EdgeInsets.all(15),
      child: MarkdownBody(data: '''
# Dependencies

### List pubspec dependencies

name | score pub ^ | imports count ^ | LoC | go to (pub & repository)
                                     over shows changelog & readme

- Pubviz button
- Upgrade button (with preview of all changelog)
- 

'''),
    );
  }
}
