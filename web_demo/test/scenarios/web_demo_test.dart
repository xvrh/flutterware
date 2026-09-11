import 'dart:io';

import 'package:flutterware/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/demo/recorded_project.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/demo/recording.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:brewline/shop/shop_strings.dart';
import 'package:path/path.dart' as p;

import '../../demo/entries.g.dart';

/// The web demo, walked under the harness: the same shell, the same
/// recording and the same compiled-in previews the page is built from, so a
/// change to what the page shows is a step that moved here first.
///
/// The previews are drawn inline — a guest in this very tree, no process —
/// which is what lets the walk settle under FakeAsync.
void main() {
  // As the page does: the shop's strings are the demo app's assets, bundled
  // under its package name in this program.
  ShopStrings.assetPackage = 'brewline';
  final recording = FileScenarioArtifacts(
    p.normalize(p.join(Directory.current.path, '..', 'app', 'demo', 'fixture')),
  );

  scenario('Previews of the demo app, drawn inline', (s) async {
    var shell = recordedShell(recording: recording, previews: webDemoPreviews);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell));
    await s.tap('Previews', shot: Shot('The catalog'));
    // Already on a phone: the recorded manifest declares one, and the shop
    // is a phone app. That matters before the tree opens — at "Fit" into the
    // half-height stage the tree leaves, a screen that does not scroll
    // overflows, the example's own finding, which an embedder guest keeps to
    // itself and a guest drawn inline lands on the studio.
    await s.tap('Menu', shot: Shot('The menu, on a phone'));
    await s.tap('Elements', shot: Shot('Its tree'));
    await s.tap('Cart', shot: Shot('The cart'));
  });
}
