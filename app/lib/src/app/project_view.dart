import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/app/ui/menu.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import '../dependencies/screen.dart';
import '../icon/screen.dart';
import '../overview/screen.dart';
import '../project.dart';
import '../test_runner/screen.dart';
import 'menu.dart';
import 'paths.dart' as paths;

class ProjectView extends StatelessWidget {
  final Project project;

  const ProjectView(this.project, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AppColors.menuBackground,
                width: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: Menu(project)),
                    MenuLine(
                      selected: false,
                      onTap: () {
                        //TODO(xha): go to changelog, feature tour etc...
                      },
                      type: LineType.leaf,
                      depth: 0,
                      child: Text(
                        'Flutter Studio v0.1.0',
                        style: TextStyle(color: AppColors.selection),
                      ),
                    ),
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
                    paths.home: (route) => OverviewScreen(project),
                    paths.dependencies: (route) => DependenciesScreen(project),
                    paths.tests: (route) => TestRunnerScreen(project),
                    paths.icon: (route) => IconScreen(project),
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
}
