import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/inspect/node.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/run_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/inspect.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';

/// The Screen tab, mounted for real against a fake reading.
///
/// **This exists because a `capture` did not catch the bug it guards.** The
/// pane reads on mount and tells the page above it so the strip can show a
/// spinner — a `setState` on an *ancestor*, from inside `initState`. Debug
/// throws there and the read never started; release compiles the assertion out
/// and it worked. `capture` builds the GUI in release, so the screenshot that
/// reviewed the change showed a tree that a real debug session never drew.
void main() {
  late Directory runDir;
  late Directory worktree;

  setUp(() {
    runDir = Directory.systemTemp.createTempSync('fw-run-panel-');
    worktree = Directory.systemTemp.createTempSync('fw-run-panel-wt-');
    RunCore.runDirProvider = () => runDir.path;
    RunCore.debugLive = false;
  });

  tearDown(() {
    RunCore.runDirProvider = flutterwareRunDir;
    RunCore.debugLive = true;
    for (var dir in [runDir, worktree]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the screen pane finishes its read and draws both halves', (
    tester,
  ) async {
    var core = RunCore(
      PluginHost(
        id: runPluginId,
        label: 'Run',
        worktree: Worktree(path: worktree.path),
        workspace: Workspace(
          root: worktree.path,
          declared: [Pkg('.')],
          discovered: ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: const {},
      ),
    );
    addTearDown(core.dispose);

    var handle = RunHandle(
      worktree: worktree.path,
      // The host's own name, or the run reads as another checkout's and the
      // header says `held by …` instead of offering reload.
      worktreeName: Worktree(path: worktree.path).name,
      device: 'macos',
      deviceName: 'macOS',
      entrypoint: 'lib/main.dart',
      entrypointName: 'App',
      launcherPid: pid,
      vmService: 'ws://127.0.0.1:1/x=/ws',
      startedAt: DateTime.now(),
    ).publish(runDir.path);

    // Real file and socket work, so it cannot run inside `testWidgets`' fake
    // async zone — the future would simply never complete.
    await tester.runAsync(core.computeAll);
    core.debugSetProbe(handle, const RunProbe(app: true, launcher: true));
    core.debugRead = (_) async => InspectRead(
      tree: InspectTree(
        entryId: null,
        root: const InspectNode(
          id: '',
          type: 'MyApp',
          createdByLocalProject: true,
        ),
      ),
      image: Uint8List.fromList(_onePixelPng),
    );

    var address = ValueNotifier(
      Address(
        worktree: 'wt',
        plugin: runPluginId,
        segments: [handle.key, 'screen'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: AddressRoot(
          address: address,
          onChanged: (a) => address.value = a,
          child: Builder(builder: RunPlugin(core).buildPanel),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The read completed. Before the fix this threw inside `initState`, the
    // read never ran, and the pane said `Reading the app…` for ever.
    expect(tester.takeException(), isNull);
    expect(find.text('Reading the app…'), findsNothing);

    // Both halves of the Screen tab, from the one reading.
    expect(find.text('MyApp'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    // The design's tabs, and the header above them.
    expect(find.text('Screen'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('reloadable'), findsOneWidget);
  });
}

/// The smallest valid PNG — `Image.memory` has to decode something.
const _onePixelPng = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
  3, 1, 1, 0, 24, 221, 141, 219, 0, 0, 0, 0, 73, 69, 78, 68,
  174, 66, 96, 130,
];
