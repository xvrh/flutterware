import 'dart:io';

import 'package:flutter/material.dart';
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
    await s.tap('Themed icon', shot: Shot('The themed icon'));
    await s.tap('Dependencies', shot: Shot('Not recorded'));
  });

  /// A scenario of the scenarios panel: the recorded run of the demo app's
  /// coffee shop, drawn by the studio, photographed by the harness. Opening a
  /// scenario runs it, and over a recording that run is a read — which is
  /// what lets this walk settle under FakeAsync.
  scenario('Scenarios of a recorded project', (s) async {
    var shell = recordedShell(recording: recording);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell));
    await s.tap('Scenarios', shot: Shot('The suite'));
    await s.tap('Order a cappuccino', shot: Shot('A recorded run'));
    await s.tap(const Target.containing('1 · Welcome'), shot: Shot('A step'));
  });

  /// Around the run: the flow zoomed out to the whole walk and back in, and
  /// the device picker — a pick re-runs, and over a recording the run comes
  /// back as what was recorded, which the chip says.
  scenario('Looking around a recorded run', (s) async {
    var shell = recordedShell(recording: recording);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell));
    await s.tap('Scenarios');
    await s.tap('Order a cappuccino', shot: Shot('The run'));
    await s.tap(Icons.zoom_out);
    await s.tap(Icons.zoom_out);
    await s.tap(Icons.zoom_out, shot: Shot('Zoomed out to the whole walk'));
    await s.tap(Icons.zoom_in, shot: Shot('Zoomed back in'));
    await s.tap('iPhone 16 (default)', shot: Shot('The device picker'));
    await s.tap(
      const Target.nth('iPhone SE', 0),
      shot: Shot('Picked another phone'),
    );
  });

  /// A step's page: the inspector over the recorded tree, every tab, the
  /// next step and the way back.
  scenario('Inspecting a recorded step', (s) async {
    var shell = recordedShell(recording: recording);
    await shell.start(recordedProjectRoot);
    await s.pumpWidget(ShellApp(shell));
    await s.tap('Scenarios');
    await s.tap('Order a cappuccino');
    await s.tap(const Target.containing('1 · Welcome'), shot: Shot('The step'));
    await s.tap(
      const Target.containing('Text("Brewline")'),
      shot: Shot('A widget picked in the tree'),
    );
    await s.tap('Semantics', shot: Shot('Semantics'));
    await s.tap('Texts', shot: Shot('Texts'));
    await s.tap('Events', shot: Shot('Events'));
    await s.tap(
      const Target.containing('2 · Menu'),
      shot: Shot('The next step'),
    );
    await s.tap(Icons.arrow_back, shot: Shot('Back to the flow'));
  });
}
