import 'package:flutter/material.dart';
import 'package:flutterware_app/src/overview/service.dart';
import 'package:flutterware_app/src/utils/router_outlet.dart';
import '../app/paths.dart' as paths;
import '../app/project_view.dart';
import '../dependencies/model/service.dart';
import '../icon/model/service.dart';
import '../project.dart';
import '../ui.dart';
import '../ui/colors.dart';
import '../utils/async_value.dart';
import 'package:path/path.dart' as p;

import '../icon/image_provider.dart';

class OverviewScreen extends StatelessWidget {
  final Project project;

  const OverviewScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return ListView(
      primary: false,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      children: [
        Text(
          'PROJECT OVERVIEW',
          style: theme.textTheme.bodySmall,
        ),
        _ProjectInfoCard(project),
        const SizedBox(height: 30),
        Text(
          'TOOLS',
          style: theme.textTheme.bodySmall,
        ),
        _ToolsCard(),
      ],
    );
  }
}

class _ProjectInfoCard extends StatelessWidget {
  final Project project;

  const _ProjectInfoCard(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Icon(project),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<Snapshot<Pubspec>>(
                    valueListenable: project.pubspec,
                    builder: (context, projectSnapshot, child) {
                      var version = projectSnapshot.data?.version;
                      String? versionString;
                      if (version != null) {
                        versionString =
                            '${version.major}.${version.minor}.${version.patch}';
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            projectSnapshot.data?.name ??
                                p.basename(project.directory.path),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (versionString != null)
                            Container(
                              decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(2)),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(
                                'v$versionString',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black45,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  Text(
                    p.normalize(project.absolutePath),
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      child: Text(
                        'ANDROID | IOS | MACOS | WINDOWS',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Text(
                      'Dependencies: 10 directs, 32 transitives',
                      style: const TextStyle(
                          //color: AppColors.selection,
                          //decoration: TextDecoration.underline,
                          //fontSize: 12,
                          ),
                    ),
                  ),
                  Text(
                    'Dart: v2.17',
                    style: const TextStyle(),
                  ),
                  Text(
                    'Version: v2.17',
                    style: const TextStyle(),
                  ),
                  /*const SizedBox(width: 10),
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(2)),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          'v1.0.0',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black45),
                        ),
                      ),
                      Text('Android'),
                    ],
                  ),*/
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _ToolsCard extends StatelessWidget {
  const _ToolsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Link('Launcher icon update', '/project/${paths.icon}'),
            _Link('Dependencies overview', '/project/${paths.dependencies}'),
            _Link('Hot-reloadable, visual test runner',
                '/project/${paths.tests}'),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  final String title;
  final String url;

  const _Link(this.title, this.url);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('• '),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: () {
              context.router.go(url);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.link,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      child: InkWell(
        onTap: () {},
        child: Container(
          //decoration: BoxDecoration(
          //    color: Colors.white,
          //    border: Border.all(width: 1, color: Colors.black12),
          //    borderRadius: BorderRadius.circular(3)),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Dependencies',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  InkWell(
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Manage',
                        style: const TextStyle(
                          // color: AppColors.selection,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              //Divider(),
              Text('10 directs  |  72 transitives'),
              //Text('72 transitives'),
              //InkWell(
              //  onTap: () {},
              //  child: Padding(
              //    padding: const EdgeInsets.symmetric(horizontal: 8.0),
              //    child: Text(
              //      'Manage',
              //      style: const TextStyle(
              //        color: AppColors.selection,
              //        decoration: TextDecoration.underline,
              //      ),
              //    ),
              //  ),
              //),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCard2 extends StatelessWidget {
  const _HomeCard2({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      child: Container(
        //decoration: BoxDecoration(
        //  color: Colors.white,
        //  border: Border.all(width: 1, color: Colors.black12),
        //),
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Code metrics',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 5),
                //Expanded(child: Divider()),
              ],
            ),
            //Divider(),
            Text('20256 Lines of Code'),
            Text('72 files'),
          ],
        ),
      ),
    );
  }
}

class _HomeCard3 extends StatelessWidget {
  const _HomeCard3({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.white,
      surfaceTintColor: Colors.orange,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      child: Container(
        //decoration: BoxDecoration(
        //  color: Colors.white,
        //  border: Border.all(width: 1, color: Colors.black12),
        //),
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Flutter Studio',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 5),
                //Expanded(child: Divider()),
                Container(
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2)),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    'v1.0.0',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                    ),
                  ),
                )
              ],
            ),
            //Divider(),
            Text('Changelog'),
            Text('Feature tour'),
            Text('Help'),
          ],
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  final Project project;

  const _Icon(this.project);

  @override
  Widget build(BuildContext context) {
    return Material(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black12, width: 1),
      ),
      child: InkWell(
        onTap: () {
          context.router.go('/project/${paths.icon}');
        },
        child: SizedBox(
          width: IconService.previewSize.toDouble(),
          height: IconService.previewSize.toDouble(),
          child: ValueListenableBuilder<Snapshot<SampleIcon>>(
            valueListenable: project.icons.sample,
            builder: (context, snapshot, child) {
              var file = snapshot.data?.file;
              if (file != null) {
                return Image(image: AppIconImageProvider(file));
              }
              return const SizedBox();
            },
          ),
        ),
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
      child: ValueListenableBuilder<Snapshot<Dependencies>>(
        valueListenable: project.dependencies.dependencies,
        builder: (context, snapshot, child) {
          var data = snapshot.data;
          return Text(
            '${data?.dependencies.length ?? '-'} dependencies (${data?.directs.length ?? '-'} directs, ${data?.transitives.length} transitives)',
            style: const TextStyle(
                //color: AppColors.selection,
                ),
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
