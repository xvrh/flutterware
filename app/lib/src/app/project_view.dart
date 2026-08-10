import 'package:flutter/material.dart';
import 'package:flutterware/devbar.dart';
import '../about/screen.dart';
import '../drawing/menu.dart';
import '../drawing/screen.dart';
import '../overview/screen.dart';
import '../project.dart';
import '../ui/side_menu.dart';
import '../utils/async_value.dart';
import '../utils/value_stream_builder.dart';
import '../utils/router_outlet.dart';
import 'paths.dart' as paths;

final enableDrawingPath = FeatureFlag('enableDrawingPath', false);

class ProjectView extends StatelessWidget {
  final Project project;

  const ProjectView(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SideMenu(
          bottom: [AboutMenuItem()],
          children: [
            SingleLineGroup(
              child: MenuLink(
                url: paths.home,
                title: ValueStreamBuilder<Snapshot<Pubspec>>(
                  stream: project.pubspec,
                  builder: (context, snapshot, child) {
                    return Text(snapshot.data?.name ?? '');
                  },
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
              ],
            ),
            if (enableDrawingPath.dependsOnValue(context)) DrawingMenu(project),
          ],
        ),
        Expanded(
          child: RouterOutlet({
            paths.home: (route) => OverviewScreen(project),
            // No dependencies route. That screen reads the shell's address for
            // which package it is on and where inside itself it is, and this
            // pre-shell view has no address to give it. It lives in the
            // `flutterware.dependencies` plugin now. Neither is there a
            // launcher-icon route: that screen is the `flutterware.launcher_icon`
            // plugin now.
            paths.drawing: (route) => DrawingScreen(project),
          }, onNotFound: (_) => paths.home),
        ),
      ],
    );
  }
}
