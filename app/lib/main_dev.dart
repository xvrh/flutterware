import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/flutter_sdk.dart';
import 'src/app/app.dart';
import 'src/globals.dart';
import 'src/project.dart';
import 'src/utils/debug.dart';

void main() async {
  setupDebugLogger();
  await globals.resourceCleaner.initialize();
  var flutterSdks = await FlutterSdkPath.findSdks();
  var flutterSdk = flutterSdks.first;
  print('Use SDK: ${flutterSdk.root}');
  runApp(SingleProjectApp(Project('../examples/example', flutterSdk)));
}
