import 'package:flutter/material.dart';
import 'package:flutterware_app/src/ui/side_menu.dart';
import 'package:flutterware_app/src/utils/router_outlet.dart';
import '../about/screen.dart';
import '../dependencies/screen.dart';
import '../icon/screen.dart';
import '../overview/screen.dart';
import '../project.dart';
import '../test_runner/screen.dart';
import '../utils/async_value.dart';
import 'paths.dart' as paths;

class ProjectView extends StatelessWidget {
  final Project project;

  const ProjectView(this.project, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SideMenu(
          bottom: [
            AboutMenuItem(),
          ],
          children: [
            LogoTile(
              name: 'Flutterware',
              version: 'ALPHA',
            ),
            SingleLineGroup(
              child: MenuLink(
                url: paths.home,
                title: Row(
                  children: [
                    Icon(
                      Icons.home,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ValueListenableBuilder<Snapshot<Pubspec>>(
                        valueListenable: project.pubspec,
                        builder: (context, snapshot, child) {
                          return Text(snapshot.data?.name ?? '');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            CollapsibleMenu(
              title: Text('Project'),
              children: [
                MenuLink(
                  url: paths.dependencies,
                  title: Text('Pub dependencies'),
                ),
                MenuLink(
                  url: paths.icon,
                  title: Text('Launcher icon'),
                ),
              ],
            ),
            CollapsibleMenu(
              title: Text('Tests'),
              children: [],
            ),
          ],
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
    );
  }
}
