import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import '../utils/router_outlet.dart';
import 'flow_graph.dart';
import 'protocol/api.dart';
import 'toolbar.dart';
import 'ui/menu_tree.dart';

class TestRunView extends StatelessWidget {
  final TestRunnerApi client;
  final Widget? reloadToolbar;

  const TestRunView(
    this.client, {
    Key? key,
    this.reloadToolbar,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ToolBarScope(
      child: RouterOutlet(
        {
          ':testId': (args) {
            return RunView(
              client,
              BuiltList(TreePath.fromEncoded(args['testId']).nodes),
              reloadToolbar: reloadToolbar,
            );
          },
        },
      ),
    );
  }
}
