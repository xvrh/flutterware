import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/constants.dart';
import 'package:flutter_studio_app/src/flutter_sdk.dart';
import 'package:logging/logging.dart';
import 'src/app/single_project.dart';
import 'src/project.dart';

const projectPath = String.fromEnvironment(projectDefineKey);
const flutterSdkPath = String.fromEnvironment(flutterSdkDefineKey);

void main() async {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(print);
  runApp(SingleProjectApp(Project(projectPath, FlutterSdkPath(flutterSdkPath))));
}
