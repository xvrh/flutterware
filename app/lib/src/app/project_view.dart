import 'package:flutter/material.dart';
import 'package:flutterware/devbar.dart';
import '../about/screen.dart';
import '../dependencies/list.dart';
import '../drawing/menu.dart';
import '../drawing/screen.dart';
import '../icon/image_provider.dart';
import '../icon/model/service.dart';
import '../icon/screen.dart';
import '../overview/screen.dart';
import '../project.dart';
import '../test_runner/menu.dart';
import '../test_runner/screen.dart';
import '../ui/side_menu.dart';
import '../ui_book/ui_book.dart';
import '../utils/async_value.dart';
import '../utils/router_outlet.dart';
import 'paths.dart' as paths;

final enableDrawingPath = FeatureFlag('enableDrawingPath', false);
final enableUIBook = FeatureFlag('enableUIBook', false);

class ProjectView extends StatelessWidget {
  final Project project;

  const ProjectView(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    const iconWidth = 25.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SideMenu(
          bottom: [
            AboutMenuItem(),
          ],
          children: [
            SingleLineGroup(
              child: MenuLink(
                url: paths.home,
                title: Row(
                  children: [
                    ValueListenableBuilder<Snapshot<SampleIcon>>(
                      valueListenable: project.icons.sample,
                      builder: (context, snapshot, child) {
                        var data = snapshot.data?.file;

                        if (data != null) {
                          return Image(
                            image: AppIconImageProvider(data),
                            width: iconWidth,
                            height: iconWidth,
                          );
                        } else {
                          return const SizedBox(width: iconWidth);
                        }
                      },
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
            TestMenu(project),
            if (enableUIBook.dependsOnValue(context)) UIBookMenu(),
            if (enableDrawingPath.dependsOnValue(context)) DrawingMenu(project),
          ],
        ),
        Expanded(
          child: RouterOutlet(
            {
              paths.home: (route) => OverviewScreen(project),
              paths.dependencies: (route) => DependenciesScreen(project),
              paths.tests: (route) => TestRunnerScreen(project),
              paths.uiBook: (route) => UIBookScreen(project),
              paths.icon: (route) => IconScreen(project),
              paths.drawing: (route) => DrawingScreen(project),
            },
            onNotFound: (_) => paths.home,
          ),
        ),
      ],
    );
  }
}
