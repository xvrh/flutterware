import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/internals/remote_log.dart';
import 'package:flutterware/internals/remote_log_adapter.dart';
import 'package:flutterware_app/src/constants.dart';
import 'package:flutterware_app/src/flutter_sdk.dart';
import 'package:logging/logging.dart';
import 'src/app/app.dart';
import 'src/globals.dart';
import 'src/project.dart';



void main() async {
  var projectPath = Platform.environment[projectDefineKey];
  var flutterSdkPath = Platform.environment[flutterSdkDefineKey];

  if (projectPath==null || flutterSdkPath==null) {
    throw Exception(
        'This entry point need to be run with some --dart-define parameters. Use main_dev.dart for development.');
  }

  var remoteLoggerUrl = Platform.environment[remoteLoggerUrlKey];
  if (remoteLoggerUrl != null && remoteLoggerUrl.isNotEmpty) {
    var remoteLoggerClient = RemoteLogClient(Uri.parse(remoteLoggerUrl));
    globals.logger = remoteLoggerClient;
  }

  _setupLogger();
  await globals.resourceCleaner.initialize();
  runApp(
      SingleProjectApp(Project(projectPath, FlutterSdkPath(flutterSdkPath))));
}

void _setupLogger() {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(globals.logger.printLogRecord);
}
