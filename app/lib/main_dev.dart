import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/flutter_sdk.dart';
import 'package:logging/logging.dart';
import 'src/app/single_project.dart';
import 'src/project.dart';

void main() async {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(print);
  var flutterSdks = await FlutterSdkPath.findSdks();
  var flutterSdk = flutterSdks.first;
  print('Use SDK: ${flutterSdk.root}');
  runApp(SingleProjectApp(Project('../examples/example', flutterSdk)));
}
