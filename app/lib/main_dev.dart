import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'src/context.dart';
import 'src/app/project_view.dart' show enableDrawingPath, enableUIBook;
import 'src/devbar.dart';
import 'src/plugins/manifest_loader.dart';
import 'src/plugins/native/registry.dart';
import 'src/shell/shell_controller.dart';
import 'src/shell/shell_view.dart';
import 'src/utils/debug.dart';
import 'src/utils/flutter_sdk.dart';

final _logger = Logger('main_dev');

/// In-IDE entry point: runs the shell against `examples/example`.
void main() async {
  setupDebugLogger();
  var appContext = AppContext(logger: LogClient.print());
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

  runApp(
    AppDevbar(
      flags: [
        enableDrawingPath.withDefaultValue,
        enableUIBook.withDefaultValue,
      ],
      child: ShellApp(shell),
    ),
  );

  // Discovery runs a subprocess; the shell renders its empty state until it
  // resolves rather than blocking the first frame.
  await shell.start('../examples/example');
}
