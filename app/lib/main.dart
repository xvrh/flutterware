import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutterware/internals/remote_log.dart';
import 'package:flutterware/internals/remote_log_adapter.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/constants.dart';
import 'src/flutter_sdk.dart';
import 'src/globals.dart';
import 'src/project.dart';

void main() async {
  var projectPath = Platform.environment[projectDefineKey];
  var flutterSdkPath = Platform.environment[flutterSdkDefineKey];

  if (projectPath == null || flutterSdkPath == null) {
    throw Exception(
        'This entry point need to be run with some --dart-define parameters. Use main_dev.dart for development.');
  }

  var remoteLoggerUrl = Platform.environment[remoteLoggerUrlKey];
  Uri? loggerUri;
  if (remoteLoggerUrl != null && remoteLoggerUrl.isNotEmpty) {
    loggerUri = Uri.parse(remoteLoggerUrl);
    var remoteLoggerClient = RemoteLogClient(loggerUri);
    globals.logger = remoteLoggerClient;
  }
  var project = Project(
    projectPath,
    FlutterSdkPath(flutterSdkPath),
    loggerUri: loggerUri,
  );

  _setupLogger();
  await globals.resourceCleaner.initialize();
  runApp(
    SingleProjectApp(project),
  );
}

void _setupLogger() {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(globals.logger.printLogRecord);
}
