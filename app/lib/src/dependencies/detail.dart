import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';

import '../app/ui/breadcrumb.dart';
import '../project.dart';
import '../utils.dart';
import '../utils/async_value.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class DependencyDetailScreen extends StatelessWidget {
  final Project project;
  final String packageName;

  const DependencyDetailScreen(this.project, this.packageName, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Snapshot<Dependencies>>(
      valueListenable: project.dependencies.dependencies,
      builder: (context, snapshot, child) {
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        } else if (snapshot.isLoading) {
          return LoadingPanel();
        } else {
          var dependency = snapshot.requireData.dependencies[packageName];
          if (dependency == null) {
            return ErrorWidget('$packageName not found');
          }
          return _DetailScreen(project, dependency);
        }
      },
    );
  }
}

class _DetailScreen extends StatelessWidget {
  final Project project;
  final Dependency dependency;

  const _DetailScreen(this.project, this.dependency);

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Breadcrumb(
              onBack: () {
                context.router.go('/project/dependencies');
              },
              children: [
                BreadcrumbEntry.overview,
                BreadcrumbEntry(
                    title: Text('Dependencies'), url: '/project/dependencies')
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                dependency.name,
                style: theme.textTheme.headlineMedium,
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Info', height: 35),
                Tab(text: 'Readme', height: 35),
                Tab(text: 'Changelog', height: 35),
              ],
            ),
            Container(
              color: AppColors.tabDivider,
              height: 1,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _InfoTab(dependency),
                  Text('README'),
                  Text('Changelog'),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                context.router.go('/project/dependencies');
              },
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 18),
                  const SizedBox(width: 5),
                  Text('Back to list'),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  final Dependency dependency;

  const _InfoTab(this.dependency);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: ListView(
            primary: false,
            children: [
              _InfoRow(
                label: Text('Version'),
                value: Text("1.0.0"),
              ),
              _InfoRow(
                label: Text('Pub'),
                value: Text("100%, 205 likes, 130 points"),
              ),
              _InfoRow(
                label: Text('Github'),
                value: Text("100 stars 50 forks (thecompany/therepository)"),
              ),
              _InfoRow(
                label: Text('Imports'),
                value: Text("2 imports in Dart code"),
              ),
              _InfoRow(
                label: Text('Transitive'),
                value: Column(
                  children: [
                    for (var dependantPath in dependency.dependencyPaths)
                      Text(dependantPath.join(' < ')),
                  ],
                ),
              ),
              Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Text(
                  'Metrics',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              _InfoRow(
                label: Text('Lines of Code'),
                value: Text("123654 (Dart), 456 (Java)"),
              ),
              _InfoRow(
                label: Text('Size'),
                value: Text("12 MO + 123 files"),
              ),
              Divider(),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final Widget label;
  final Widget value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.black54, fontSize: 13),
              child: label,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: value,
            ),
          ),
        ],
      ),
    );
  }
}
