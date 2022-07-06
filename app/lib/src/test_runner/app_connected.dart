import 'package:built_collection/built_collection.dart';
import 'ui/menu_tree.dart';
import '../utils/router_outlet.dart';
import 'package:flutterware/internals/test_runner.dart';
import 'package:flutter/material.dart';
import 'flow_graph.dart';
import 'protocol/api.dart';
import 'toolbar.dart';

class ConnectedScreen extends StatefulWidget {
  final TestRunnerApi client;

  const ConnectedScreen(
    this.client, {
    Key? key,
  }) : super(key: key);

  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen> {
  late Future<ProjectInfo> _project;

  @override
  void initState() {
    super.initState();

    _project = widget.client.project.loadInfo();
  }

  @override
  Widget build(BuildContext context) {
    // refactor, no need to load info like that?
    "";
    return FutureBuilder<ProjectInfo>(
      future: _project,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return ErrorWidget(snapshot.error!);
          }
          return TestRunView(widget.client, snapshot.requireData);
        } else {
          return Center(
            child: Text('Loading project...'),
          );
        }
      },
    );
  }
}

class TestRunView extends StatelessWidget {
  final TestRunnerApi client;
  final ProjectInfo projectInfo;

  const TestRunView(this.client, this.projectInfo, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ToolBarScope(
      project: projectInfo,
      child: RouterOutlet(
        {
          ':testId': (args) {
            return RunView(
              client,
              BuiltList(TreePath.fromEncoded(args['testId']).nodes),
            );
          },
        },
      ),
    );
  }
}
