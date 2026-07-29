import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutterware/src/log_client.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'src/constants.dart';
import 'src/context.dart';
import 'src/plugins/manifest_loader.dart';
import 'src/plugins/native/registry.dart';
import 'src/shell/shell_controller.dart';
import 'src/shell/shell_view.dart';
import 'src/utils/flutter_sdk.dart';

// ignore_for_file: implementation_imports

/// The production entry point: the plugin shell, against the project the CLI
/// was run from.
///
/// Requires the environment the compiled CLI sets; use `main_dev.dart` for
/// development, which is the same shell with the paths supplied by hand.
void main() async {
  var projectPath = Platform.environment[projectDefineKey];
  var appToolPath = Platform.environment[appToolPathKey];
  var flutterSdkPath = Platform.environment[flutterSdkDefineKey];

  if (projectPath == null || flutterSdkPath == null) {
    throw Exception(
      'This entry point need to be run with some Platform.environment parameters. Use main_dev.dart for development.',
    );
  }

  var appContext = AppContext(
    logger: LogClient.print(),
    // Where `native/`, `tool/catalog/` and the build directory live — the
    // copy under `~/.flutterware/`, not the user's project. The catalog needs
    // it, and only once its panel is opened.
    appToolDirectory: appToolPath != null ? Directory(appToolPath) : null,
  );
  var flutterSdk = FlutterSdkPath(flutterSdkPath);

  Logger.root
    ..level = Level.ALL
    ..onRecord.listen(appContext.logger.printLogRecord);
  await appContext.resourceCleaner.initialize();

  var shell = ShellController(
    appContext: appContext,
    flutterSdk: flutterSdk,
    registry: buildNativeRegistry(),
    manifestLoader: ManifestLoader(
      dartExecutable: p.join(flutterSdk.root, 'bin', 'dart'),
    ),
  );

  runApp(ShellApp(shell));

  // No welcome banner. It used to be printed here, and this process has no
  // terminal to print it to — `fw` owns the one it inherits, knows the plugin
  // list before the window exists, and says it there instead. What is left on
  // this stream is what belongs on it: the app's own logs.

  // After the first frame: discovery runs a subprocess, and the shell renders
  // its empty state until it resolves rather than holding up the window.
  await shell.start(projectPath);
}
