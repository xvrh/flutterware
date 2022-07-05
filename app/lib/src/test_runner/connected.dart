import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/internals/test_runner.dart';

import '../project.dart';
import 'ui/menu_tree.dart';
import '../utils/router_outlet.dart';
import 'flow_graph.dart';
import 'toolbar.dart';

/*class ConnectedTestView extends StatelessWidget {
  final Project project;

  const ConnectedTestView(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return ToolBarScope(
      project: ProjectInfo("TODO", supportedLanguages: []),
      child: RouterOutlet(
        {
          'scenario/:scenarioId': (args) {
            return RunView(
              service,
              client,
              BuiltList(
                  TreePath.fromEncoded(args['scenarioId']).nodes),
            );
          },
        },
      ),
    );
  }
}
*/
