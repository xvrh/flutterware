import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/dependencies/service.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import 'package:flutter_studio_app/src/utils/ui/loading.dart';

import '../app/ui/back_bar.dart';
import '../project.dart';
import '../ui.dart';
import '../utils/async_value.dart';

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

  const _DetailScreen(this.project, this.dependency, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackBar('All dependencies'),
          Text(dependency.name, style: theme.textTheme.headlineMedium,),
          Text('''
Version | Date update
Link Pub
Link Github
Score pub
Score Github
Number of usage in the package (+ list)
If transitive, show all import graphs (until direct dep)
LoC
Size (MB + number of files)
Tabs: README | CHANGELOG
All available versions?
''')
        ],
      ),
    );
  }
}
