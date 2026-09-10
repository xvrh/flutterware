import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/demo/recorded_project.dart';
import 'package:flutterware_app/src/demo/recording.dart';
import 'package:flutterware_app/src/launcher_icon/ui/plate.dart';
import 'package:flutterware_app/src/plugins/scan_cache.dart';
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:path/path.dart' as p;

/// The whole studio over the recording `tool/demo/record.dart` wrote, with no
/// git, no manifest subprocess and no scan of the disk — which is the shape
/// the studio's own scenarios and the web demo open it in.
void main() {
  final recording = FileScenarioArtifacts(
    p.join(Directory.current.path, 'demo', 'fixture'),
  );

  testWidgets('opens on the recorded project and draws its launcher icons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var shell = recordedShell(recording: recording);
    addTearDown(shell.dispose);
    await shell.start(recordedProjectRoot);
    await tester.pumpWidget(ShellApp(shell));
    await tester.pumpAndSettle();

    // The rail is the recorded project's declared plugins.
    expect(find.text('Launcher icon'), findsOneWidget);
    expect(find.text('Dependencies'), findsOneWidget);

    await tester.tap(find.text('Launcher icon'));
    await tester.pumpAndSettle();

    // The example app's icons, read from the recording rather than the disk:
    // a plate per role that has files, and the flavors it declares as chips.
    expect(find.byType(IconPlate), findsWidgets);
    expect(find.text('Android'), findsWidgets);
    expect(find.text('kiosk'), findsOneWidget);
    expect(find.text('Reading the icons…'), findsNothing);
    expect(find.textContaining('Could not read'), findsNothing);
  });

  testWidgets('a plugin with nothing recorded says so', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var shell = recordedShell(recording: recording);
    addTearDown(shell.dispose);
    await shell.start(recordedProjectRoot);
    await tester.pumpWidget(ShellApp(shell));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dependencies'));
    await tester.pumpAndSettle();

    expect(find.text('Not in this recording'), findsOneWidget);
  });

  test('a scan missing from the recording is a failure, not a crash', () async {
    var scan = recordedIconScanner(recording);
    Object? failure;
    try {
      await scan(packageRoot: () => '/none', packagePath: 'nope');
    } catch (e) {
      failure = e;
    }
    expect(failure, isA<ScanFailure>());
    expect('$failure', startsWith('This recording has no launcher icon scan'));
  });
}
