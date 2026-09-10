import 'dart:io';

import 'package:flutterware/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/demo/recorded_project.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/demo/recording.dart';
// ignore: implementation_imports
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:path/path.dart' as p;

import '../../demo/entries.g.dart';

/// The web demo, walked under the harness: the same shell, the same
/// recording and the same compiled-in previews the page is built from, so a
/// change to what the page shows is a step that moved here first.
///
/// The previews are drawn inline — a guest in this very tree, no process —
/// which is what lets the walk settle under FakeAsync.
void main() {
  final recording = FileScenarioArtifacts(
    p.normalize(p.join(Directory.current.path, '..', 'app', 'demo', 'fixture')),
  );

  scenario('Previews of the example, drawn inline', (s) async {
    var shell = recordedShell(recording: recording, previews: webDemoPreviews);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell));
    await s.tap('Previews', shot: Shot('The catalog'));
    await s.tap('Buttons', shot: Shot('An entry, live'));
    // Staged as a phone before the tree opens: at "Fit" into the
    // half-height stage the tree leaves, the example's column of buttons
    // overflows — the example's own finding, which an embedder guest keeps
    // to itself and a guest drawn inline lands on the studio.
    await s.tap('Fit');
    await s.tap('iPhone 16', shot: Shot('Staged as a phone'));
    await s.tap('Elements', shot: Shot('Its tree'));
    await s.tap('On a phone', shot: Shot('Another entry, on the phone'));
  });
}
