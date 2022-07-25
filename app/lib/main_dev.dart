import 'package:flutter/material.dart';
import 'package:flutterware_app/src/flutter_sdk.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/globals.dart';
import 'src/project.dart';
import 'src/utils/debug.dart';

final _logger = Logger('main_dev');

void main() async {
  setupDebugLogger();
  await globals.resourceCleaner.initialize();
  var flutterSdks = await FlutterSdkPath.findSdks();
  var flutterSdk = flutterSdks.first;
  _logger.info('Use SDK: ${flutterSdk.root}');
  runApp(SingleProjectApp(Project('../examples/example', flutterSdk)));
}
