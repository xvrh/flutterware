import 'dart:io';

import 'package:flutterware/flutter_test.dart';
import 'package:flutterware_app/src/demo/recorded_project.dart';
import 'package:flutterware_app/src/demo/recording.dart';
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:path/path.dart' as p;

/// The studio, driven by its own harness, over the recording
/// `tool/demo/record.dart` wrote.
///
/// What this buys is the thing every other project gets from scenarios and
/// the studio never had: a deterministic picture of each screen, kept run to
/// run, so a change to the rail or a panel shows up as a step that moved. The
/// project it opens is a recording rather than a checkout — no git, no
/// manifest subprocess, no scan of the disk — which is what makes the walk
/// repeatable under FakeAsync. See `lib/src/demo/recorded_project.dart`.
///
/// The file end of the recording, not the asset end: the harness runs under
/// FakeAsync, where a synchronous read lands and an asset fetch would not.
void main() {
  final recording = FileScenarioArtifacts(
    p.join(Directory.current.path, 'demo', 'fixture'),
  );

  scenario('Launcher icons of a recorded project', (s) async {
    var shell = recordedShell(recording: recording);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell), shot: Shot('Home'));
    await s.tap('Launcher icon', shot: Shot('Launcher icons'));
    await s.tap('kiosk', shot: Shot('Kiosk flavor'));
    await s.tap('Dependencies', shot: Shot('Not recorded'));
  });

  /// A scenario of the scenarios panel: the recorded run of the example's
  /// coffee shop, drawn by the studio, photographed by the harness. Opening a
  /// scenario runs it, and over a recording that run is a read — which is
  /// what lets this walk settle under FakeAsync.
  scenario('Scenarios of a recorded project', (s) async {
    var shell = recordedShell(recording: recording);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell));
    await s.tap('Scenarios', shot: Shot('The suite'));
    await s.tap('mobile');
    await s.tap('shop_test.dart', shot: Shot('A file unfolded'));
    await s.tap('Order a cappuccino', shot: Shot('A recorded run'));
    await s.tap(const Target.containing('1 · Welcome'), shot: Shot('A step'));
  });
}
