import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';

import '../app/ui/menu_tree.dart';
import '../utils/router_outlet.dart';
import 'flow_graph.dart';
import 'toolbar.dart';

class ConnectedTestView extends StatelessWidget {
  const ConnectedTestView({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('TODO');
    //return ToolBarScope(
    //  project: projectInfo,
    //  child: RouterOutlet(
    //    {
    //      'scenario/:scenarioId': (args) {
    //        return RunView(
    //          service,
    //          client,
    //          BuiltList(
    //              TreePath.fromEncoded(args['scenarioId']).nodes),
    //        );
    //      },
    //    },
    //  ),
    //);
  }
}
