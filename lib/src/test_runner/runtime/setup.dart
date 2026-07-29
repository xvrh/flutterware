import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../../log_client.dart';
import 'runner.dart';
import 'setup_io.dart' if (dart.library.html) 'setup_web.dart';

void runTests(
  Uri serverUri,
  Map<String, void Function()> Function() tests, {
  required String flutterBinPath,
  bool Function(String)? translationPredicate,
  String? projectName,
  List<String>? supportedLanguages,
  String? rootProjectPath,
  String? projectPackageName,
  Brightness? defaultStatusBarBrightness,
}) async {
  _setupLogger();
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

/// Sends this test process's log records to its stdout.
///
/// It used to choose between stdout and a websocket back to the GUI, off a
/// `loggerUri` threaded from `PackageRef` through `Project` and into the
/// generated entry point. Nothing ever set it, so the branch was dead the whole
/// way down and the plumbing has gone with it.
void _setupLogger() {
  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(LogClient.print().printLogRecord);
}
