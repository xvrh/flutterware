import 'dart:io';
import 'dart:math';

import 'package:flutter_studio_app/src/utils/fitted_app.dart';
import 'package:flutter_studio_app/src/standalone/workspace.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../ui.dart';
import '../utils/router_outlet.dart';
import 'package:flutter/material.dart';

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

class _App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Again, new start'),
      ],
    );
  }
}
