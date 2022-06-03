import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/project_info/screen.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';

import '../dependencies/screen.dart';
import '../project.dart';
import '../test_runner/screen.dart';
import '../ui.dart';
import '../utils/data_loader.dart';
import 'header.dart';
import 'menu.dart';
import 'ui/breadcrumb.dart';
import 'ui/side_bar.dart';
import 'paths.dart' as paths;

export 'ui/breadcrumb.dart';

class ProjectView extends StatefulWidget {
  final Project project;

  const ProjectView(this.project, {Key? key}) : super(key: key);

  @override
  State<ProjectView> createState() => ProjectViewState();

  static ProjectViewState of(BuildContext context) =>
      context.findAncestorStateOfType<ProjectViewState>()!;
}

class ProjectViewState extends State<ProjectView> {
  final _headerKey = GlobalKey<HeaderState>();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<Snapshot<Pubspec>>(
          valueListenable: widget.project.pubspec,
          builder: (context, snapshot, child) {
            return Header(
              snapshot.data?.name ?? snapshot.error?.toString() ?? '',
              key: _headerKey,
            );
          },
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SidebarHeader(title: Text('Project')),
                    Expanded(child: Menu(widget.project)),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.separator,
                ),
                width: 1,
              ),
              Expanded(
                child: RouterOutlet(
                  {
                    paths.home: (route) => ProjectInfoScreen(),
                    paths.dependencies: (route) => DependenciesScreen(),
                    paths.tests: (route) => TestRunnerScreen(),
                  },
                  onNotFound: (_) => paths.home,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  HeaderState get header => _headerKey.currentState!;

  void setBreadcrumb(Iterable<BreadcrumbItem> breadcrumb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      header.setItemsBuilder((context) => breadcrumb);
    });
  }
}
