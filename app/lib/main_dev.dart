import 'dart:io';

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'src/context.dart';
import 'src/app/project_view.dart' show enableDrawingPath;
import 'src/devbar.dart';
import 'src/plugins/manifest_loader.dart';
import 'src/plugins/native/registry.dart';
import 'src/shell/drive_navigator.dart';
import 'src/shell/shell_controller.dart';
import 'src/shell/shell_view.dart';
import 'src/utils/debug.dart';
import 'src/utils/flutter_sdk.dart';

final _logger = Logger('main_dev');

/// The `flutterware_app` package root, which owns `native/`, `tool/catalog/`
/// and the build directory the catalog compiles into.
///
/// Passed in rather than derived: a macOS app launched by `flutter run` has a
/// working directory of `/`, so the default of `Directory.current` finds
/// nothing. Only the catalog needs it, and only when its panel is opened.
const _appRootDefine = String.fromEnvironment('FLUTTERWARE_APP_ROOT');

/// In-IDE entry point: runs the shell against flutterware's own workspace.
///
/// ```sh
/// cd app && flutter run -t lib/main_dev.dart -d macos \
///   --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)"
/// ```
void main() async {
  setupDebugLogger();
  var appContext = AppContext(
    logger: LogClient.print(),
    appToolDirectory: _appRootDefine.isEmpty ? null : Directory(_appRootDefine),
  );
  var flutterSdks = await FlutterSdkPath.findSdks();
  var flutterSdk = flutterSdks.first;
  _logger.info('Use SDK: ${flutterSdk.root}');

  var shell = ShellController(
    appContext: appContext,
    flutterSdk: flutterSdk,
    registry: buildNativeRegistry(),
    manifestLoader: ManifestLoader(
      dartExecutable: p.join(flutterSdk.root, 'bin', 'dart'),
    ),
  );
  registerDriveNavigator(shell);

  runApp(
    AppDevbar(
      flags: [enableDrawingPath.withDefaultValue],
      child: ShellApp(shell),
    ),
  );

  // Discovery runs a subprocess; the shell renders its empty state until it
  // resolves rather than blocking the first frame. The path is walked up to the
  // repo root, so this opens flutterware's own workspace.
  await shell.start('..');
}
