import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'src/demo/recorded_project.dart';
import 'src/demo/recording.dart';
import 'src/shell/shell_view.dart';

/// The studio in a browser, over a recording.
///
/// The same shell the desktop app runs, opened on the recorded project rather
/// than on a checkout — see `src/demo/recorded_project.dart`. Nothing here
/// runs a process, reads a disk or opens a socket: git is a canned listing,
/// the manifest is built in-process, and the one plugin with a recording
/// behind it reads that recording out of the asset bundle. Everything else
/// says it is not recorded, which is the truth and reads better than a broken
/// panel.
///
/// This is the page the README links to: what the studio looks like, without
/// installing anything. Built with
///
/// ```sh
/// cd app && fvm flutter build web -t lib/main_demo_web.dart
/// ```
void main() {
  // The same reason the export viewer gives: the engine's default strategy
  // rewrites the URL at boot, and this page has nowhere it wants to go.
  setUrlStrategy(null);
  var shell = recordedShell(recording: const AssetRecording());
  runApp(ShellApp(shell));
  unawaited(shell.start(recordedProjectRoot));
}
