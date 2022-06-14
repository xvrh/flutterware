import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_studio_app/src/project_info/service.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import '../app/paths.dart' as paths;
import '../app/project_view.dart';
import '../project.dart';
import '../ui.dart';
import '../utils/async_value.dart';
import 'package:path/path.dart' as p;

class ProjectInfoScreen extends StatelessWidget {
  final Project project;

  const ProjectInfoScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    ProjectView.of(context).setBreadcrumb([]);

    return ListView(
      primary: false,
      padding: const EdgeInsets.all(15),
      children: [
        Row(
          children: [
            SizedBox(width: 50, height: 50, child: _Icon(project)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<Snapshot<Pubspec>>(
                    valueListenable: project.pubspec,
                    builder: (context, projectSnapshot, child) {
                      return Text(
                        projectSnapshot.data?.name ??
                            p.basename(project.directory.path),
                        style: theme.textTheme.headlineSmall,
                      );
                    },
                  ),
                  Text(
                    p.normalize(project.absolutePath),
                    style: const TextStyle(color: Colors.black45),
                  ),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 20),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '120 dependencies',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text('4 directs, 200 transitives'),
                TextButton(onPressed: () {}, child: Text('MANAGE')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('24 523 Lines of Code'),
                TextButton(onPressed: () {}, child: Text('MANAGE')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('0 App Test'),
                TextButton(onPressed: () {}, child: Text('START')),
              ],
            ),
          ),
        ),
        //TODO(xha): re-organise to be more beautiful
        // Title - More info
        const SizedBox(height: 20),
        _Dependencies(project),
        const SizedBox(height: 20),
        _Metrics(project),
      ],
    );
  }
}

class _Icon extends StatelessWidget {
  final Project project;

  const _Icon(this.project);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        context.router.go('/${paths.icon}');
      },
      child: ValueListenableBuilder<Snapshot<SampleIcon>>(
        valueListenable: project.info.icon,
        builder: (context, snapshot, child) {
          var file = snapshot.data?.file;
          if (file != null) {
            return Image.file(file);
          }
          return const SizedBox();
        },
      ),
    );
  }
}

class _Dependencies extends StatelessWidget {
  final Project project;

  const _Dependencies(this.project);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        context.router.go('/${paths.dependencies}');
      },
      child: ValueListenableBuilder<Snapshot<DependenciesSummary>>(
        valueListenable: project.info.dependencies,
        builder: (context, snapshot, child) {
          var data = snapshot.data;
          return Text(
            '${data?.total ?? '-'} dependencies (${data?.direct ?? '-'} directs, ${data?.transitive} transitives)',
            style: const TextStyle(color: AppColors.selection),
          );
        },
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  final Project project;

  const _Metrics(this.project);

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Code metrics',
          style: theme.textTheme.bodyLarge,
        ),
        Row(
          children: [
            Text('Lines of Code'),
            Text(
              '24 325',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        //TODO(xha): Create its own menu entry
        // Add a graph with test vs normal code
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 400,
            child: DataTable(columns: [
              DataColumn(label: Text('Folder')),
              DataColumn(label: Text('Files')),
              DataColumn(label: Text('Lines')),
            ], rows: [
              DataRow(
                cells: [
                  DataCell(Text('Main')),
                  DataCell(Text('50')),
                  DataCell(Text('200 000')),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(Text('Tests')),
                  DataCell(Text('50')),
                  DataCell(Text('200 000')),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(Text('Other')),
                  DataCell(Text('50')),
                  DataCell(Text('200 000')),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(Text('Total')),
                  DataCell(Text('50')),
                  DataCell(Text('200 000')),
                ],
              ),
            ]),
          ),
        )
      ],
    );
  }
}

/*
MarkdownBody(data: '''
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
'''
 */
