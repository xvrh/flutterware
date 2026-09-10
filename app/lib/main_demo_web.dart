import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

import 'src/demo/recorded_project.dart';
import 'src/demo/recording.dart';
import 'src/shell/shell_view.dart';

/// The studio in a browser, over a recording.
///
/// The same shell the desktop app runs, opened on the recorded project rather
/// than on a checkout — see `src/demo/recorded_project.dart`. Nothing here
/// runs a process, reads a disk or opens a socket: git is a canned listing,
/// the manifest is built in-process, and the one plugin with a recording
/// behind it fetches that recording from `demo/fixture/` beside the page.
/// Everything else says it is not recorded, which is the truth and reads
/// better than a broken panel.
///
/// This is the page the README links to: what the studio looks like, without
/// installing anything. Built with
///
/// ```sh
/// cd app && fvm dart run tool/demo/build_web.dart
/// ```
///
/// which is `flutter build web` on this file plus the recording copied
/// beside it — and what `integration_test/web_demo_test.dart` opens in a
/// real browser.
void main() {
  // The same reason the export viewer gives: the engine's default strategy
  // rewrites the URL at boot, and this page has nowhere it wants to go.
  setUrlStrategy(null);
  WidgetsFlutterBinding.ensureInitialized();
  // Semantics on from the first frame, not behind the "enable accessibility"
  // placeholder the engine draws otherwise. It is what a screen reader gets,
  // and it is the only DOM a browser test can find a tab by: the page is
  // one canvas without it.
  _semantics = SemanticsBinding.instance.ensureSemantics();
  // Relative to the document's `<base href>`, which is what `--base-href`
  // wrote and what every other relative URL on the page resolves against —
  // where `Uri.base` is the address bar, and an address typed without its
  // trailing slash would resolve one directory up.
  var recording = HttpScenarioArtifacts(
    Uri.parse(web.document.baseURI).resolve('demo/fixture/'),
  );
  var shell = recordedShell(recording: recording);
  runApp(ShellApp(shell));
  unawaited(shell.start(recordedProjectRoot));
}

/// Held for the life of the page; disposing it would turn semantics back off.
// ignore: unused_element
SemanticsHandle? _semantics;
