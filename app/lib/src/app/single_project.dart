import 'dart:io';
import 'dart:math';

import 'package:flutter_studio_app/src/utils/fitted_app.dart';
import 'package:flutter_studio_app/src/standalone/workspace.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../flutter_sdk.dart';
import '../project.dart';
import '../ui.dart';
import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';

import 'project_view.dart';

final _logger = Logger('app');

class SingleProjectApp extends StatelessWidget {
  final Project project;

  const SingleProjectApp(this.project, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RouterOutlet.root(
      child: FittedApp(
        minimumSize: Size(550, 400),
        child: MaterialApp(
          title: 'Flutter Studio',
          theme: appTheme(),
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
