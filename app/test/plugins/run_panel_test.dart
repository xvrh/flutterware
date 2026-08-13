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
import 'package:flutterware_app/src/plugins/native/run_address.dart';
import 'package:flutterware_app/src/plugins/native/run_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/run/handle.dart';
import 'package:flutterware_app/src/run/inspect.dart';
import 'package:flutterware_app/src/run/inventory.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/split_button.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/utils/daemon/device.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

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
    var screenshot = Uint8List.fromList(_onePixelPng);
    core.debugRead = (_) async => InspectRead(
      tree: InspectTree(
        entryId: null,
        root: const InspectNode(
          id: '',
          type: 'MyApp',
          createdByLocalProject: true,
        ),
      ),
      image: screenshot,
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

    // Decode the screenshot here rather than leaving a codec in flight. The
    // pumps above run in fake async, so `Image.memory` only schedules its
    // decode; the real work would then land in whichever test runs next, which
    // reports it as an image-resource exception that test never caused. Same
    // bytes instance, so this is the provider the widget is already waiting on.
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(screenshot),
        tester.element(find.byType(Image)),
      ),
    );
    await tester.pump();

    // The read completed. Before the fix this threw inside `initState`, the
    // read never ran, and the pane said `Reading the app…` for ever.
    expect(tester.takeException(), isNull);
    expect(find.text('Reading the app…'), findsNothing);

    // Both halves of the Screen tab, from the one reading.
    expect(find.text('MyApp'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    // **The detail pane must not read this reader's blindness as the widget's
    // shape.** A VM-service tree carries no layout for any node, and the pane
    // used to answer that with "lays nothing out of its own — a provider or a
    // builder" on every one of them, `Scaffold` included. It says who is not
    // looking instead.
    await tester.tap(find.text('MyApp'));
    await tester.pump();
    expect(find.textContaining('Lays nothing out'), findsNothing);
    expect(find.textContaining('Structure and source only'), findsOneWidget);

    // The design's tabs, and the header above them — the run named as one
    // phrase and the controls spelled out. No capability pill here: this run
    // is reloadable, which is the normal state; the pill only appears when
    // something is missing.
    expect(find.text('Screen'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('App \u2192 macOS'), findsOneWidget);
    expect(find.text('reloadable'), findsNothing);
    expect(find.text('Hot reload'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // Hot restart is the split button's alternative, built only while the
    // menu is open.
    expect(find.text('Hot restart'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Hot reload'),
          matching: find.byType(FwSplitButton),
        ),
        matching: find.byIcon(Icons.expand_more),
      ),
    );
    await tester.pump();
    expect(find.text('Hot restart'), findsOneWidget);
  });

  testWidgets('the New run page offers only the devices the entry point '
      'declares, and reads its flavor rather than asking for it', (
    tester,
  ) async {
    File(p.join(worktree.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: app\nflutter:\n  default-flavor: dev\n');
    File(p.join(worktree.path, 'lib', 'main_kiosk.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
    DeviceCache.write(runDir.path, const [
      DaemonDevice(id: 'phone', name: 'Pixel', platformType: 'android'),
      DaemonDevice(
        id: 'macos',
        name: 'macOS',
        platformType: 'macos',
        ephemeral: false,
      ),
    ]);

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
        config: const {
          'packages': [
            {
              'path': '.',
              'entrypoints': [
                {
                  'path': 'lib/main_kiosk.dart',
                  'name': 'Kiosk',
                  'platforms': ['mobile'],
                },
              ],
            },
          ],
        },
      ),
    );
    addTearDown(core.dispose);

    // One run in the ledger, purely so the desk is not drawn under the form.
    // The desk is the whole machine and lists this Mac on purpose; the claim
    // under test is about the *picker*, and with both on screen no assertion
    // can tell them apart.
    RunHandle(
      worktree: worktree.path,
      worktreeName: Worktree(path: worktree.path).name,
      device: 'phone',
      entrypoint: 'lib/main_kiosk.dart',
      launcherPid: pid,
      startedAt: DateTime.now(),
    ).publish(runDir.path);
    await tester.runAsync(core.computeAll);

    var address = ValueNotifier(
      Address(
        worktree: 'wt',
        plugin: runPluginId,
        segments: const [newRunSegment],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        // The shell puts the panel inside one; the other test gets away
        // without because it never builds a text field.
        home: Scaffold(
          body: AddressRoot(
            address: address,
            onChanged: (a) => address.value = a,
            child: Builder(builder: RunPlugin(core).buildPanel),
          ),
        ),
      ),
    );
    await tester.pump();

    // The entry point is the first decision, and the device list below it is
    // the mobile half of a desk that also holds this Mac.
    expect(find.text('Kiosk'), findsWidgets);
    expect(find.text('Pixel'), findsWidgets);
    // The one that matters. This Mac is on the desk and in the cache, and the
    // only reason it is nowhere on this page is that `Kiosk` said `mobile`.
    expect(find.text('macOS'), findsNothing);
    expect(find.text('Kiosk runs on mobile'), findsOneWidget);

    // The flavor is read, not asked for: `default-flavor: dev` in the pubspec
    // is the project having already answered.
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('from the pubspec’s default-flavor'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // And it is one click away when this run really does need another.
    await tester.tap(find.text('Override'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Use dev'), findsOneWidget);
  });

  testWidgets("the New run page comes back holding last time's knobs", (
    tester,
  ) async {
    // Running the same thing again should be opening this page and pressing
    // Start. `lastLaunch` carried a `defines` map the form stopped filling in
    // when defines were deleted, so it came back empty every time — the values
    // somebody had actually chosen were the ones being dropped.
    File(p.join(worktree.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: app\n');
    File(p.join(worktree.path, 'lib', 'main.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync("void main({String apiHost = 'localhost'}) {}");
    DeviceCache.write(runDir.path, const [
      DaemonDevice(id: 'phone', name: 'Pixel', platformType: 'android'),
    ]);

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
        config: const {
          'packages': [
            {
              'path': '.',
              'entrypoints': [
                {'path': 'lib/main.dart', 'name': 'App'},
              ],
            },
          ],
        },
      ),
    );
    addTearDown(core.dispose);
    // One run in the ledger, so the desk is not drawn under the form — it
    // starts the device daemon, and a real process is not this test's subject.
    RunHandle(
      worktree: worktree.path,
      worktreeName: Worktree(path: worktree.path).name,
      device: 'phone',
      entrypoint: 'lib/main.dart',
      launcherPid: pid,
      startedAt: DateTime.now(),
    ).publish(runDir.path);
    await tester.runAsync(core.computeAll);
    core.lastLaunch = (
      device: 'phone',
      package: '.',
      entrypoint: 'lib/main.dart',
      flavor: null,
      knobs: {'apiHost': 'staging.example.com'},
    );

    var address = ValueNotifier(
      Address(
        worktree: 'wt',
        plugin: runPluginId,
        segments: const [newRunSegment],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: AddressRoot(
            address: address,
            onChanged: (a) => address.value = a,
            child: Builder(builder: RunPlugin(core).buildPanel),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('staging.example.com'), findsOneWidget);
  });
}

/// One opaque white pixel: signature, IHDR, IDAT, IEND.
///
/// It has to decode, not merely look like a PNG. An undecodable blob does not
/// fail the test that mounts it — nothing awaits the codec — it fails whichever
/// test runs next, as an image-resource exception with no visible cause.
const _onePixelPng = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, //
  73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
  8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0,
  13, 73, 68, 65, 84, 120, 218, 99, 96, 96, 96, 248,
  15, 0, 1, 4, 1, 0, 128, 187, 209, 91, 0, 0,
  0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];
