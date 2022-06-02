import 'dart:io';
import 'dart:math';

import '../../project.dart';
import 'main_tab_bar.dart';
import 'package:flutter_studio_app/src/utils/fitted_app.dart';
import 'package:flutter_studio_app/src/standalone/workspace.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../ui.dart';
import '../../utils/router_outlet.dart';
import 'package:flutter/material.dart';
import 'home.dart';
import 'project/screen.dart';

final _logger = Logger('app');

class StudioApp extends StatelessWidget {
  const StudioApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: FittedApp(
        child: MaterialApp(
          title: 'Flutter Studio',
          theme: appTheme(),
          home: Scaffold(
            body: _App(),
          ),
          initialRoute: '/',
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}

class _App extends StatefulWidget {
  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  Workspace? _workspace;

  @override
  void initState() {
    super.initState();

    _loadWorkspace();
  }

  void _loadWorkspace() async {
    var appDocDir = await getApplicationSupportDirectory();
    var workspacePath = p.join(appDocDir.path, 'workspace.json');
    var workspace = await Workspace.load(File(workspacePath));
    _logger.finer('Workspace loaded from: $workspacePath');
    if (!mounted) return;
    setState(() {
      _workspace = workspace;
    });
  }

  @override
  Widget build(BuildContext context) {
    var workspace = _workspace;

    if (workspace == null) {
      return Center(child: CircularProgressIndicator());
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MainTabBar(workspace),
          Expanded(
            child: ValueListenableBuilder<Project?>(
              valueListenable: workspace.selectedProject,
              builder: (context, project, child) {
                if (project == null) {
                  return HomeScreen(workspace);
                } else {
                  return ProjectScreen(project);
                }
              },
            ),
          ),
        ],
      );
    }
  }

  @override
  void dispose() {
    _workspace?.dispose();
    super.dispose();
  }
}
