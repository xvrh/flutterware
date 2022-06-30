import 'package:flutter_studio_app/src/utils/fitted_app.dart';
import '../project.dart';
import '../ui/theme.dart';
import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';

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
            body: ProjectView(project),
          ),
          initialRoute: '/',
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}
