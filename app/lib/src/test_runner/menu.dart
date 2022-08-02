import 'package:flutter/material.dart';
import '../project.dart';
import '../ui/side_menu.dart';
import 'daemon_toolbar.dart';
import 'listing.dart';
import 'model/service.dart';
import 'protocol/api.dart';

class TestMenu extends StatelessWidget {
  final Project project;

  const TestMenu(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return CollapsibleMenu(
      title: Text('Tests'),
      children: [
        MenuLink(
          url: 'tests/home',
          title: Text('Introduction'),
        ),
        DaemonToolbar(project),
        _listing(),
      ],
    );
  }

  Widget _listing() {
    return StreamBuilder<List<TestRunnerApi>>(
      stream: project.tests.clients,
      initialData: project.tests.clients.value,
      builder: (context, snapshot) {
        var clients = snapshot.requireData;
        if (clients.isEmpty) {
          return ValueListenableBuilder<DaemonState>(
            valueListenable: project.tests.state,
            builder: (context, state, child) {
              if (state is! DaemonState$Stopped) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1),
                    ),
                  ),
                );
              } else {
                return const SizedBox();
              }
            },
          );
        } else {
          var client = clients.last;
          return TestListingView(project.tests, client);
        }
      },
    );
  }
}
