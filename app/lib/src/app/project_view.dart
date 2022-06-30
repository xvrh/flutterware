import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/ui/side_menu.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import '../dependencies/screen.dart';
import '../icon/screen.dart';
import '../overview/screen.dart';
import '../project.dart';
import '../utils/async_value.dart';
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
              SideMenu(children: [
                LogoTile(name: 'Flutterware', version: 'v0.2.0', onTap: () {}),
                SingleLineGroup(
                  child: MenuLink(
                    url: '/${paths.home}',
                    title: Row(
                      children: [
                        Icon(
                          Icons.home,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<Snapshot<Pubspec>>(
                          valueListenable: project.pubspec,
                          builder: (context, snapshot, child) {
                            return Text(snapshot.data?.name??'');
                          }
                        ),
                      ],
                    ),
                  ),
                ),
                CollapsibleMenu(
                  title: Text('Pub dependencies'),
                  children: [
                    MenuLink(
                      url: '/${paths.dependencies}',
                      title: Text('Overview'),
                    ),
                  ],
                ),
                CollapsibleMenu(
                  title: Text('Tests'),
                  children: [

                  ],
                ),
                CollapsibleMenu(
                  title: Text('Deployment'),
                  children: [
                    MenuLink(
                      url: '/${paths.icon}',
                      title: Text('Launcher icon'),
                    ),
                  ],
                ),
              ]),
              Expanded(
                child: RouterOutlet(
                  {
                    paths.home: (route) => OverviewScreen(project),
                     paths.dependencies: (route) => DependenciesScreen(project),
                    // paths.tests: (route) => TestRunnerScreen(project),
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
