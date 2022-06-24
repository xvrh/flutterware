import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/test_runner/app_connected.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';

import '../app/project_view.dart';
import '../project.dart';
import 'menu.dart';
import 'protocol/api.dart';

class TestRunnerScreen extends StatelessWidget {
  final Project project;

  const TestRunnerScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([
      BreadcrumbItem(Text('Test runner')),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DaemonToolbar(project),
        Expanded(
          child: RouterOutlet(
            {
              '': (r) => _HomeScreen(),
              'run': (r) => _RunScreen(project),
            },
            onNotFound: (r) => '',
          ),
        ),
      ],
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('''Explain app test feature
Link to doc
Button "add a test"
Screenshot of expected workflow    
        
''');
  }
}

class _RunScreen extends StatelessWidget {
  final Project project;

  const _RunScreen(this.project, {super.key});

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
