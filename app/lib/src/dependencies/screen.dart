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
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: Text('Reload'),
                      onTap: () {
                        project.dependencies.dependencies.refresh();
                      },
                    ),
                  ],
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
    var theme = Theme.of(context);
    var headerStyle = theme.textTheme.titleMedium;

    yield Text(
      'Direct dependencies (${dependencies.directs.length})',
      style: headerStyle,
    );
    yield _table(dependencies.directs);
    yield const SizedBox(height: 30);
    yield Text(
      'Transitive dependencies (${dependencies.transitives.length})',
      style: headerStyle,
    );
    yield _table(dependencies.transitives);
  }

  Widget _table(List<Dependency> dependencies) {
    return DataTable(showCheckboxColumn: false, columns: [
      DataColumn(label: Text('Package')),
      DataColumn(label: Text('Version')),
      DataColumn(label: Text('Pub')),
      DataColumn(label: Text('GitHub')),
    ], rows: [
      for (var dependency in dependencies)
        DataRow(
          onSelectChanged: (selected) {
            print('Tap ${dependency.name}');
          },
          cells: [
            DataCell(Text(dependency.name)),
            DataCell(
              Tooltip(
                message: 'Upgrade available: BREAKING 3.0.0',
                child: Row(
                  children: [
                    Text(dependency.lockDependency.version),
                    Icon(Icons.upgrade, size: 15),
                  ],
                ),
              ),
            ),
            DataCell(
              Tooltip(
                message: '33% popularity / 100 likes / 130 points',
                child: Text('97%'),
              ),
            ),
            DataCell(
              Tooltip(
                message: '130 stars, 3 forks',
                child: Row(
                  children: [
                    Text('130'),
                    Icon(Icons.star_outline, size: 15),
                  ],
                ),
              ),
            ),
          ],
        ),
    ]);
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
