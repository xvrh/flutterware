import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_studio_app/src/dependencies/service.dart';

import '../app/project_view.dart';
import '../app/ui/breadcrumb.dart';
import '../project.dart';
import '../utils/async_value.dart';
import '../utils/ui/error_panel.dart';
import '../utils/ui/loading.dart';

class DependenciesScreen extends StatelessWidget {
  final Project project;

  const DependenciesScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([
      BreadcrumbItem(Text('Dependencies')),
    ]);
    var theme = Theme.of(context);
    return ValueListenableBuilder<Snapshot<Dependencies>>(
      valueListenable: project.dependencies.dependencies,
      builder: (context, snapshot, child) {
        var data = snapshot.data;
        var error = snapshot.error;

        return ListView(
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dependencies',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            if (data != null)
              ..._dependencies(context, data)
            else if (error != null)
              ErrorPanel(
                message: 'Failed to load dependencies',
                onRetry: project.dependencies.dependencies.refresh,
              )
            else
              LoadingPanel(),
          ],
        );
      },
    );
  }

  Iterable<Widget> _dependencies(
      BuildContext context, Dependencies dependencies) sync* {
    //TODO(xha): skip source: sdk & source: path
    yield Text('Directs');
    for (var dependency in dependencies.directs) {
      yield ListTile(
        title: Text(dependency.lockDependency.name),
      );
    }
    yield Text('Transitives');
    for (var dependency in dependencies.transitives) {
      yield ListTile(
        title: Text(dependency.lockDependency.name),
      );
    }
  }
}

var _ = '''
# Dependencies

### List pubspec dependencies

name | score pub ^ | imports count ^ | LoC | go to (pub & repository)
                                     over shows changelog & readme

- Pubviz button
- Upgrade button (with preview of all changelog)
- 

''';
