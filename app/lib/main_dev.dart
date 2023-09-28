import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/app/project_view.dart';
import 'src/context.dart';
import 'src/devbar.dart';
import 'src/project.dart';
import 'src/utils/debug.dart';
import 'src/utils/flutter_sdk.dart';

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
    AppDevbar(
      flags: [
        enableDrawingPath.withDefaultValue,
        enableUIBook.withDefaultValue,
      ],
      child: SingleProjectApp(
        Project(appContext, '../examples/example', flutterSdk),
      ),
    ),
  );
}
