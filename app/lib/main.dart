import 'package:flutter/material.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:flutterware_app/src/flutter_sdk.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/globals.dart';
import 'src/project.dart';

const projectPath = String.fromEnvironment(projectDefineKey);
const flutterSdkPath = String.fromEnvironment(flutterSdkDefineKey);

void main() async {
  if (projectPath.isEmpty || flutterSdkPath.isEmpty) {
    throw Exception(
        'This entry point need to be run with some --dart-define parameters. Use main_dev.dart for development.');
  }

  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(print);

  await globals.resourceCleaner.initialize();
  runApp(
      SingleProjectApp(Project(projectPath, FlutterSdkPath(flutterSdkPath))));
}
