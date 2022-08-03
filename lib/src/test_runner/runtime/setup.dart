import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../../logs/remote_log_adapter.dart';
import '../../logs/remote_log_client.dart';
import 'runner.dart';
import 'setup_io.dart' if (dart.library.html) 'setup_web.dart';

void runTests(
  Uri serverUri,
  Map<String, void Function()> Function() tests, {
  required String flutterBinPath,
  Uri? loggerUri,
  bool Function(String)? translationPredicate,
  String? projectName,
  List<String>? supportedLanguages,
  String? rootProjectPath,
  String? projectPackageName,
  Brightness? defaultStatusBarBrightness,
}) async {
  _setupLogger(loggerUri);
  var bundleParams = BundleParameters(
    flutterBinPath: flutterBinPath,
    translationPredicate: translationPredicate,
    rootProjectPath: rootProjectPath,
    projectPackageName: projectPackageName,
  );
  await Runner(
    () => createChannel(serverUri),
    mainFunctions: tests,
    bundle: () async => createBundle(bundleParams),
    onConnected: onConnected,
  ).run();
}

class BundleParameters {
  final bool Function(String) translationPredicate;
  final String flutterBinPath;
  final String? rootProjectPath;
  final String? projectPackageName;

  BundleParameters({
    required this.rootProjectPath,
    required this.flutterBinPath,
    bool Function(String)? translationPredicate,
    required this.projectPackageName,
  }) : translationPredicate =
            translationPredicate ?? _defaultTranslationPredicate;

  static bool _defaultTranslationPredicate(String key) =>
      key.endsWith('.json') && key.contains('translations');
}

void _setupLogger(Uri? loggerUri) {
  LogClient logger;
  if (loggerUri != null) {
    logger = RemoteLogClient(loggerUri);
  } else {
    logger = LogClient.print();
  }

  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(logger.printLogRecord);
}
