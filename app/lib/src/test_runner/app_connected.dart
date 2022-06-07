import 'package:built_collection/built_collection.dart';
import '../app/header.dart';
import '../app/ui/menu_tree.dart';
import '../utils/router_outlet.dart';
import 'package:flutter_studio/internals/test_runner.dart';
import 'package:flutter/material.dart';
import '../ui.dart';
import 'flow_graph.dart';
import 'listing.dart';
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
    return FutureBuilder<ProjectInfo>(
      future: _project,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return ErrorWidget(snapshot.error!);
          }
          return ProjectView(widget.client, snapshot.requireData);
        } else {
          return Center(
            child: Text('Loading project...'),
          );
        }
      },
    );
  }
}

class ProjectView extends StatefulWidget {
  final TestRunnerApi client;
  final ProjectInfo projectInfo;

  const ProjectView(this.client, this.projectInfo, {Key? key})
      : super(key: key);

  @override
  State<ProjectView> createState() => ProjectViewState();

  static ProjectViewState of(BuildContext context) =>
      context.findAncestorStateOfType<ProjectViewState>()!;
}

class ProjectViewState extends State<ProjectView> {
  final _headerKey = GlobalKey<HeaderState>();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Header(widget.projectInfo.name, key: _headerKey),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 220, child: TestListingView(widget.client)),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.separator,
                ),
                width: 1,
              ),
              Expanded(
                child: ToolBarScope(
                  project: widget.projectInfo,
                  child: RouterOutlet(
                    {
                      'scenario/:scenarioId': (args) {
                        return RunView(
                          widget.client,
                          BuiltList(
                              TreePath.fromEncoded(args['scenarioId']).nodes),
                        );
                      },
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  HeaderState get header => _headerKey.currentState!;
}
