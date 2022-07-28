import 'dart:async';
import 'package:flutter/material.dart';
import '../project.dart';
import '../utils/router_outlet.dart';
import 'app_connected.dart';
import 'daemon_toolbar.dart';
import 'help.dart';
import 'model/daemon.dart' show MessageLevel;
import 'protocol/api.dart';

class TestRunnerScreen extends StatefulWidget {
  final Project project;

  const TestRunnerScreen(this.project, {super.key});

  @override
  State<TestRunnerScreen> createState() => _TestRunnerScreenState();
}

class _TestRunnerScreenState extends State<TestRunnerScreen> {
  late StreamSubscription _messageSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = widget.project.tests.daemonMessage.listen((event) {
      Color background, foreground;
      switch (event.type) {
        case MessageLevel.info:
          background = Colors.black12;
          foreground = Colors.black87;
          break;
        case MessageLevel.warning:
          background = Colors.orange;
          foreground = Colors.black87;
          break;
        case MessageLevel.error:
          background = Colors.red;
          foreground = Colors.white;
          break;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            event.message,
            style: TextStyle(color: foreground),
          ),
          backgroundColor: background,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return RouterOutlet(
      {
        'home': (r) => HelpScreen(),
        'run': (r) => _RunScreen(widget.project),
      },
      onNotFound: (r) => 'home',
    );
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    super.dispose();
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
          return TestRunView(client,
              reloadToolbar: SmallDaemonToolbar(project));
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }
}
