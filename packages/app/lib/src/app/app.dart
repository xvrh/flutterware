import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';
import '../test/app.dart';
import '../test/service.dart';
import 'dashboard.dart';

class DevStudioApp extends StatelessWidget {
  const DevStudioApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: MaterialApp(
        title: 'Dev Studio',
        home: DashboardScreen(
          scenario: ScenarioAppWithServer(
            serviceFactory: (clients) => ScenarioService(clients),
          ),
        ),
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
