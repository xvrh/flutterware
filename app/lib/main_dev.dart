import 'package:flutter/material.dart';
import 'package:flutterware/src/logs/remote_log_client.dart'; // ignore: implementation_imports
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/context.dart';
import 'src/flutter_sdk.dart';
import 'src/project.dart';
import 'src/utils/debug.dart';

final _logger = Logger('main_dev');

void main() async {
  setupDebugLogger();
  var appContext = AppContext(
    logger: LogClient.print(),
  );
  var flutterSdks = await FlutterSdkPath.findSdks();
  var flutterSdk = flutterSdks.first;
  _logger.info('Use SDK: ${flutterSdk.root}');
  runApp(
    SingleProjectApp(
      Project(appContext, '../examples/example', flutterSdk),
    ),
  );
}
