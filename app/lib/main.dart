import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutterware/internals/remote_log.dart';
import 'package:flutterware/internals/remote_log_adapter.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/constants.dart';
import 'src/context.dart';
import 'src/flutter_sdk.dart';
import 'src/project.dart';

void main() async {
  var projectPath = Platform.environment[projectDefineKey];
  var flutterSdkPath = Platform.environment[flutterSdkDefineKey];

  if (projectPath == null || flutterSdkPath == null) {
    throw Exception(
        'This entry point need to be run with some Platform.environment parameters. Use main_dev.dart for development.');
  }

  var remoteLoggerUrl = Platform.environment[remoteLoggerUrlKey];
  Uri? loggerUri;
  RemoteLogClient? remoteLoggerClient;
  if (remoteLoggerUrl != null && remoteLoggerUrl.isNotEmpty) {
    loggerUri = Uri.parse(remoteLoggerUrl);
    remoteLoggerClient = RemoteLogClient(loggerUri);
  }
  var appContext = AppContext(
    logger: remoteLoggerClient ?? LogClient.print(),
  );
  var project = Project(
    appContext,
    projectPath,
    FlutterSdkPath(flutterSdkPath),
    loggerUri: loggerUri,
  );

  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(appContext.logger.printLogRecord);
  await appContext.resourceCleaner.initialize();

  runApp(
    SingleProjectApp(project),
  );

  appContext.logger.printBox(
      '''
Discover the features:
- Test runner with hot-reload
- Pub dependencies manager
- Launcher icon manager
- ...

Contribute your ideas: https://github.com/xvrh/flutterware
'''
          .trim(),
      title: 'Flutterware GUI is ready');
}
