import 'dart:io';

import 'package:flutterware/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/demo/recorded_project.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/demo/recording.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:flutterware_example/shop/shop_strings.dart';
import 'package:path/path.dart' as p;

import '../../demo/entries.g.dart';

/// The web demo, walked under the harness: the same shell, the same
/// recording and the same compiled-in previews the page is built from, so a
/// change to what the page shows is a step that moved here first.
///
/// The previews are drawn inline — a guest in this very tree, no process —
/// which is what lets the walk settle under FakeAsync.
void main() {
  // As the page does: the shop's strings are the example's assets, bundled
  // under its package name in this program.
  ShopStrings.assetPackage = 'flutterware_example';
  final recording = FileScenarioArtifacts(
    p.normalize(p.join(Directory.current.path, '..', 'app', 'demo', 'fixture')),
  );

  scenario('Previews of the example, drawn inline', (s) async {
    var shell = recordedShell(recording: recording, previews: webDemoPreviews);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell));
    await s.tap('Previews', shot: Shot('The catalog'));
    await s.tap('Menu', shot: Shot('The menu, live'));
    // Staged as a phone before the tree opens: the shop is a phone app, and
    // at "Fit" into the half-height stage the tree leaves, a screen that
    // does not scroll overflows — the example's own finding, which an
    // embedder guest keeps to itself and a guest drawn inline lands on the
    // studio.
    await s.tap('Fit');
    await s.tap('iPhone 16', shot: Shot('Staged as a phone'));
    await s.tap('Elements', shot: Shot('Its tree'));
    await s.tap('Cart', shot: Shot('The cart, on the phone'));
  });
}
