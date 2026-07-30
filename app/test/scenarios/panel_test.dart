import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

/// The flow page, smoke-deep: opening it starts a run, the settled run draws
/// the step strip and the texts panel, and tapping a step writes the address.
/// The run itself is a fake — the real runner is `runner_test.dart`'s job.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_scenarios_panel_test');
  });

  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('runs on open, draws the flow, selects by address', (
    tester,
  ) async {
    var core = ScenariosCore(
      PluginHost(
        id: scenariosPluginId,
        label: 'Scenarios',
        worktree: Worktree(path: root.path),
        workspace: Workspace(
          root: root.path,
          declared: [Pkg('.')],
          discovered: ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: {
          'packages': [
            {'path': '.'},
          ],
        },
      ),
    );
    var runner = _FakeRunner();
    core.debugInstallRunner('.', runner);
    var plugin = ScenariosPlugin(core);

    var address = ValueNotifier(
      Address(
        worktree: 'wt',
        plugin: scenariosPluginId,
        segments: ['.', 'test', 'scenarios', 'a_test.dart', 'A'],
        axes: {'device': 'iphone-se', 'brightness': 'dark'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: AddressRoot(
          address: address,
          onChanged: (a) => address.value = a,
          child: Builder(builder: plugin.buildPanel),
        ),
      ),
    );

    // Opening the page started the run; the fake settles in microtasks and
    // the deferred notification lands on the next pump.
    await tester.pump();
    await tester.pump();

    expect(runner.runs, 1);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('0 · shot'), findsOneWidget);
    expect(find.text('1 · end'), findsOneWidget);
    expect(find.text('VISIBLE TEXTS'), findsOneWidget);
    // The last step is the default selection, and its texts are the ones
    // shown.
    expect(find.text('bye', findRichText: true), findsOneWidget);

    // Selecting a step is an address write, not local state.
    await tester.tap(find.text('0 · shot'));
    await tester.pump();
    expect(address.value.segments.last, '0');
    expect(find.text('hello', findRichText: true), findsOneWidget);

    // The address's axes went into the run, and the toolbar reads them back.
    expect(
      runner.seenAxes.single,
      const ScenarioAxes(device: 'iphone-se', brightness: 'dark'),
    );
    expect(find.text('iPhone SE'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    // An axis change is an address write, and the page notices and re-runs.
    address.value = address.value.withAxes({'language': 'fr'});
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(runner.runs, 2);
    expect(runner.seenAxes.last.language, 'fr');

    // Run again — the button is the same demand as opening was.
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
    expect(runner.runs, 3);
  });
}

class _FakeRunner extends ScenarioRunner {
  _FakeRunner()
    : super(packageRoot: '/none', directory: 'none', flutterSdkRoot: '/none');

  var runs = 0;
  final seenAxes = <ScenarioAxes>[];

  @override
  Future<Map<String, Object?>> run({
    required String outDir,
    String? file,
    String? scenario,
    ScenarioAxes axes = const ScenarioAxes(),
  }) async {
    runs++;
    seenAxes.add(axes);
    Directory(outDir).createSync(recursive: true);
    Map<String, Object?> step(int index, String name, String text) {
      var png = '$outDir/$index-$name.png';
      File(png).writeAsBytesSync(_transparentPng);
      return {
        'index': index,
        'name': name,
        'auto': false,
        'png': png,
        'tree': '$outDir/$index-$name.tree.json',
        'texts': [text],
      };
    }

    return {
      'ms': 5,
      'scenarios': [
        {
          'file': file,
          'name': scenario,
          'ok': true,
          'ms': 3,
          'steps': [step(0, 'shot', 'hello'), step(1, 'end', 'bye')],
        },
      ],
    };
  }

  @override
  Future<void> dispose() async {}
}

/// A 1×1 transparent PNG, so `Image.file` has a real file to point at.
const _transparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
