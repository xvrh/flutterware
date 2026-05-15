import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'src/embedder/embedder_harness_screen.dart';
import 'src/utils/flutter_sdk.dart';

/// IDE dev entrypoint: runs only the embedder harness screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var sdks = await FlutterSdkPath.findSdks();
  var flutterSdkRoot = sdks.first.root;
  // The compiled app runs with its bundle as the working dir; the `app/`
  // package root is resolved from this source file's location during dev.
  var appPackageRoot = Directory.current.path.endsWith('app')
      ? Directory.current.path
      : p.join(Directory.current.path, 'app');

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: EmbedderHarnessScreen(
      appPackageRoot: appPackageRoot,
      flutterSdkRoot: flutterSdkRoot,
    ),
  ));
}
