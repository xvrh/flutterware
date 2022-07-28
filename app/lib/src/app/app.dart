import 'package:flutter/material.dart';
import '../about/screen.dart';
import '../project.dart';
import '../ui/theme.dart';
import '../utils/fitted_app.dart';
import '../utils/router_outlet.dart';
import 'project_view.dart';

class SingleProjectApp extends StatelessWidget {
  final Project project;

  const SingleProjectApp(this.project, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: FittedApp(
        minimumSize: Size(750, 400),
        child: MaterialApp(
          title: 'Flutterware',
          theme: appTheme,
          home: Scaffold(
            body: RouterOutlet(
              {
                'project': (_) => ProjectView(project),
                'about': (_) => AboutScreen(),
              },
              onNotFound: (_) => 'project',
            ),
          ),
          initialRoute: '/',
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
