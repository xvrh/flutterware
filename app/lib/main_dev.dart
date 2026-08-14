import 'dart:io';

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'src/context.dart';
import 'src/devbar.dart';
import 'src/plugins/manifest_loader.dart';
import 'src/plugins/native/registry.dart';
import 'src/shell/shell_controller.dart';
import 'src/shell/shell_view.dart';
import 'src/utils/debug.dart';
import 'src/utils/flutter_sdk.dart';
import 'src/identity/dock_icon.dart';
import 'src/utils/window_title.dart';

final _logger = Logger('main_dev');

/// In-IDE entry point: runs the shell against flutterware's own workspace.
///
/// Launched through flutterware it is *Studio (dev)*, and [appRoot] is a knob —
/// editable on the run's Knobs tab, applied by a hot restart rather than a
/// rebuild. Launched by hand it takes the define, so an IDE run configuration
/// that predates this still works:
///
/// ```sh
/// cd app && flutter run -t lib/main_dev.dart -d macos \
///   --dart-define=FLUTTERWARE_APP_ROOT="$(pwd)"
/// ```
///
/// [appRoot] is the `flutterware_app` package root, which owns `native/`,
/// `tool/catalog/` and the build directory the catalog compiles into. Passed in
/// rather than derived: a macOS app launched by `flutter run` has a working
/// directory of `/`, so `Directory.current` finds nothing. Only the catalog
/// needs it, and only when its panel is opened.
///
/// [flutterSdkRoot] is passed in for the same reason and a stronger one. That
/// same environment is stripped, so nothing in this process can see which
/// `flutter` launched it — and flutterware does not guess: the SDK is whichever
/// one the invocation names, and here the invocation is `flutter run`, which
/// this side cannot read. So it is said out loud, as a knob or a define.
void main({
  String appRoot = const String.fromEnvironment('FLUTTERWARE_APP_ROOT'),
  String project = '..',
  String flutterSdkRoot = const String.fromEnvironment('FLUTTER_SDK_ROOT'),
}) async {
  setupDebugLogger();
  var appContext = AppContext(
    logger: LogClient.print(),
    appToolDirectory: appRoot.isEmpty ? null : Directory(appRoot),
  );
  if (flutterSdkRoot.isEmpty) {
    throw StateError(
      'main_dev needs the Flutter SDK it should use. Set the flutterSdkRoot '
      'knob on the run Knobs tab, or pass it when launching by hand:\n\n'
      r'    --dart-define=FLUTTER_SDK_ROOT="$(cd "$(dirname "$(which flutter)")/.." && pwd)"',
    );
  }
  var flutterSdk = FlutterSdkPath(flutterSdkRoot);
  _logger.info('Use SDK: ${flutterSdk.root}');

  var shell = ShellController(
    appContext: appContext,
    flutterSdk: flutterSdk,
    registry: buildNativeRegistry(),
    manifestLoader: ManifestLoader(
      dartExecutable: p.join(flutterSdk.root, 'bin', 'dart'),
      flutterRoot: flutterSdk.root,
    ),
  );
  runApp(AppDevbar(flags: const [], child: ShellApp(shell)));

  await WindowTitle.setForProject(project);

  // And the tile, which is what a user actually scans.
  DockIcon.follow(shell);

  // Discovery runs a subprocess; the shell renders its empty state until it
  // resolves rather than blocking the first frame. The path is walked up to the
  // repo root, so this opens flutterware's own workspace.
  await shell.start(project);
}
