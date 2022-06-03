import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/project_info/screen.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';

import '../dependencies/screen.dart';
import '../project.dart';
import '../ui.dart';
import '../utils/data_loader.dart';
import 'header.dart';
import 'menu.dart';

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
                  key: _headerKey);
            }),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 220,
                child: Menu(),
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
                    'home': (route) => ProjectInfoScreen(),
                    'dependencies': (route) => DependenciesScreen(),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  HeaderState get header => _headerKey.currentState!;
}
