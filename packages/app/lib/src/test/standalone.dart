import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';

class StandaloneScenarioApp extends StatelessWidget {
  final Widget app;

  const StandaloneScenarioApp(this.app, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: MaterialApp(
        title: 'Scenario runner',
        home: Scaffold(body: app),
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
