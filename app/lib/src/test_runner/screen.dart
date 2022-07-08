import 'package:flutter/material.dart';
import 'package:flutterware_app/src/test_runner/app_connected.dart';
import 'package:flutterware_app/src/test_runner/help.dart';
import 'package:flutterware_app/src/utils/router_outlet.dart';

import '../project.dart';
import 'daemon_toolbar.dart';
import 'menu.dart';
import 'protocol/api.dart';

class TestRunnerScreen extends StatelessWidget {
  final Project project;

  const TestRunnerScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return RouterOutlet(
      {
        '': (r) => HelpScreen(),
        'run': (r) => _RunScreen(project),
      },
      onNotFound: (r) => '',
    );
  }
}

class _RunScreen extends StatelessWidget {
  final Project project;

  const _RunScreen(this.project);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TestRunnerApi>>(
      stream: project.tests.clients,
      initialData: project.tests.clients.value,
      builder: (context, snapshot) {
        var clients = snapshot.requireData;
        if (clients.isNotEmpty) {
          var client = clients.last;
          return ConnectedScreen(client);
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }
}
