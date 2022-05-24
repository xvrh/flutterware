import 'dart:io';
import 'dart:math';

import 'package:flutter_studio_app/src/app/project_tabs.dart';
import 'package:flutter_studio_app/src/workspace.dart';

import '../ui.dart';
import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';
import '../test_visualizer/app.dart';
import '../test_visualizer/service.dart';
import 'home.dart';

class StudioApp extends StatelessWidget {
  const StudioApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: MaterialApp(
        title: 'Flutter Studio',
        theme: appTheme(),
        home: Scaffold(
          body: _App(),
        ),
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class _App extends StatefulWidget {
  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  //TODO(xha): load workspace from json file
  final workspace = Workspace(File('todo.json'));

  @override
  Widget build(BuildContext context) {
    var mediaQuery = MediaQuery.of(context);
    return FittedBox(
      child: SizedBox(
        width: max(mediaQuery.size.width, 450),
        height: max(mediaQuery.size.height, 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProjectTabs(workspace),
            Expanded(child: HomeScreen()),
          ],
        ),
      ),
    );
  }
}
