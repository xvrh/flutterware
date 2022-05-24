import 'package:flutter_studio_app/src/app/project_tabs.dart';

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
        home: Scaffold(body: _App()),
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class _App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProjectTabs(),
        Expanded(child: HomeScreen()),
      ],
    );
  }
}
