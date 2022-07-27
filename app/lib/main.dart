import 'package:flutter/material.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:flutterware_app/src/flutter_sdk.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/globals.dart';
import 'src/project.dart';
import 'package:flutterware/internals/log.dart';

const projectPath = String.fromEnvironment(projectDefineKey);
const flutterSdkPath = String.fromEnvironment(flutterSdkDefineKey);

void main() async {
  if (projectPath.isEmpty || flutterSdkPath.isEmpty) {
    throw Exception(
        'This entry point need to be run with some --dart-define parameters. Use main_dev.dart for development.');
  }
  _setupLogger();
  await globals.resourceCleaner.initialize();
  runApp(
      SingleProjectApp(Project(projectPath, FlutterSdkPath(flutterSdkPath))));
}

void _setupLogger() {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen((e) {
      var message = '[${e.level}] $e';
      if (e.error != null) {
        message += '\n${e.error}';
      }
      if (e.stackTrace != null) {
        message += '\n${e.stackTrace}';
      }

      var log = Log(message, e.level.value);
      print(log.toJsonString());
    });
}
