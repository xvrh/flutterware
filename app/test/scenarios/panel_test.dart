import 'dart:convert';
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
import 'package:flutterware_app/src/ui/matched_text.dart';
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
    // Master/detail: the scenario list stays visible beside the flow.
    expect(find.text('A'), findsWidgets);
    expect(find.text('test/scenarios/a_test.dart'), findsWidgets);
    // The flow: one node per step, on the graph canvas.
    expect(find.text('0 · shot'), findsOneWidget);
    expect(find.text('1 · end'), findsOneWidget);
    // The texts live on the pushed step page, not the flow.
    expect(find.text('VISIBLE TEXTS'), findsNothing);

    // The address's axes went into the run, and the toolbar reads them back.
    expect(
      runner.seenAxes.single,
      const ScenarioAxes(device: 'iphone-se', brightness: 'dark'),
    );
    expect(find.text('iPhone SE'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    // Opening a step is an address write that pushes the detail page — with
    // the inspect dock under the shot, open on Elements: the step's tree,
    // read from the file the fake wrote.
    await tester.tap(find.text('0 · shot'), warnIfMissed: false);
    await tester.pump();
    expect(address.value.segments.last, '0');
    expect(find.text('Elements'), findsOneWidget);
    expect(find.text('ShotRoot'), findsOneWidget);
    expect(find.text('ChildBox'), findsOneWidget);
    expect(find.text('VISIBLE TEXTS'), findsNothing);

    // Selecting a row is an address write; the detail pane answers.
    expect(find.text('Select a widget'), findsOneWidget);
    await tester.tap(find.text('ChildBox'));
    await tester.pump();
    expect(address.value.axes['node'], '0');
    expect(find.text('Select a widget'), findsNothing);

    // The texts moved into the dock, one tab over.
    await tester.tap(find.text('Texts'));
    await tester.pump();
    expect(find.text('VISIBLE TEXTS'), findsOneWidget);
    expect(find.text('hello', findRichText: true), findsOneWidget);

    // And its back button pops to the flow.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    expect(address.value.segments.last, 'A');
    expect(find.text('VISIBLE TEXTS'), findsNothing);

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

    // Writing another one is reachable from a pane that is not empty — here
    // still scanning, which is a state the empty-state button never sees.
    expect(find.byTooltip('New scenario'), findsOneWidget);
  });

  testWidgets('an unset device runs as the default phone', (tester) async {
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
    await tester.pump();
    await tester.pump();
    expect(runner.seenAxes.single.device, 'iphone-13');
    expect(find.text('iPhone 13'), findsOneWidget);
  });

  // A package with nothing in it is the moment the reader is certainly asking
  // how to write one, so the list pane answers with the same string `list`
  // hands an agent rather than with an empty box.
  testWidgets('an empty suite says how to write one', (tester) async {
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
    var plugin = ScenariosPlugin(core);

    // The scan runs off-isolate, and its completion is delivered to the zone
    // that started it — so under the test's fake clock it would never land.
    // Started here, in the real zone, it settles; the panel's own `track` on
    // mount is idempotent and finds it done.
    await tester.runAsync(() async {
      core.track('.');
      while (core.scanResultFor('.') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: AddressRoot(
          address: ValueNotifier(
            Address(worktree: 'wt', plugin: scenariosPluginId),
          ),
          onChanged: (_) {},
          child: Builder(builder: plugin.buildPanel),
        ),
      ),
    );
    await tester.pump();

    var hint = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(hint, contains('No scenarios in test/scenarios'));
    expect(hint, contains("import 'package:flutterware/flutter_test.dart'"));
    expect(hint, contains('fw run scenarios new'));
  });

  // …and the command it names is a button too, so a GUI reader is not sent to
  // a terminal for their first file.
  testWidgets('New scenario writes one and opens it', (tester) async {
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

    // As above: the off-isolate scan is primed in the real zone.
    await tester.runAsync(() async {
      core.track('.');
      while (core.scanResultFor('.') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    var address = ValueNotifier(
      Address(worktree: 'wt', plugin: scenariosPluginId),
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
    await tester.pump();

    // Both doors: the pane's persistent header and the empty state's call to
    // action.
    expect(find.byTooltip('New scenario'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New scenario'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'New scenario'));
    await tester.pumpAndSettle();

    // Nothing to create until it is named.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create')),
      isA<FilledButton>().having((b) => b.onPressed, 'onPressed', isNull),
    );

    await tester.enterText(find.byType(TextField), 'Around the shop');
    await tester.pump();
    // The dialog says where the file lands, as `new` derives it.
    expect(
      find.text('test/scenarios/around_the_shop_test.dart'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    // The action writes, the dialog pops, and the pop's exit transition has to
    // finish before its future — and so the address write — lands.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(
      File(
        '${root.path}/test/scenarios/around_the_shop_test.dart',
      ).readAsStringSync(),
      contains("scenario('Around the shop'"),
    );
    // And the panel went to it, which is what runs it.
    expect(address.value.segments, [
      '.',
      'test',
      'scenarios',
      'around_the_shop_test.dart',
      'Around the shop',
    ]);
    await tester.pump();
    expect(runner.runs, 1);
  });

  // A suite is a list you scan with your eyes until it isn't. The filter
  // narrows it on both of the things a row is known by — its own name and the
  // file it lives in — and lights what answered.
  testWidgets('the filter narrows on name and on file', (tester) async {
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
    core.debugInstallRunner('.', _FakeRunner());
    var plugin = ScenariosPlugin(core);

    Directory('${root.path}/test/scenarios').createSync(recursive: true);
    File('${root.path}/test/scenarios/checkout_test.dart').writeAsStringSync('''
void main() {
  scenario('Pays with a card', () {});
  scenario('Abandons the basket', () {});
}
''');
    File('${root.path}/test/scenarios/login_test.dart').writeAsStringSync('''
void main() {
  scenario('Signs in with email', () {});
}
''');

    await tester.runAsync(() async {
      core.track('.');
      while (core.scanResultFor('.') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        // The field is a `TextField`, which wants the Material the shell puts
        // under every panel.
        home: Scaffold(
          body: AddressRoot(
            address: ValueNotifier(
              Address(worktree: 'wt', plugin: scenariosPluginId),
            ),
            onChanged: (_) {},
            child: Builder(builder: plugin.buildPanel),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Pays with a card'), findsOneWidget);
    expect(find.text('Abandons the basket'), findsOneWidget);
    expect(find.text('Signs in with email'), findsOneWidget);

    // A scenario's own name keeps that row and drops the rest — including the
    // file heading of a group that lost every row.
    await tester.enterText(find.byType(TextField), 'card');
    await tester.pump();
    expect(find.text('Pays with a card', findRichText: true), findsOneWidget);
    expect(find.text('Abandons the basket'), findsNothing);
    expect(find.text('Signs in with email'), findsNothing);
    expect(find.text('login_test.dart'), findsNothing);

    // Fuzzy, not substring: `pwc` is a subsequence of the name and no
    // substring search would keep the row at all.
    await tester.enterText(find.byType(TextField), 'pwc');
    await tester.pump();
    expect(find.text('Pays with a card', findRichText: true), findsOneWidget);
    var name = tester.widget<Text>(
      find
          .descendant(of: find.byType(MatchedText), matching: find.byType(Text))
          .last,
    );
    var spans = (name.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(
      [
        for (var span in spans)
          if (span.style?.backgroundColor != null) span.text,
      ],
      ['P', 'w', 'c'],
    );

    // The file answers for everything in it: nothing here is called `login`,
    // and the whole file stays — with the heading lit, since that is where the
    // reason lives.
    await tester.enterText(find.byType(TextField), 'login');
    await tester.pump();
    expect(find.text('Signs in with email'), findsOneWidget);
    expect(find.text('Pays with a card'), findsNothing);
    var heading = tester.widget<Text>(
      find
          .descendant(of: find.byType(MatchedText), matching: find.byType(Text))
          .first,
    );
    var headingSpans = (heading.textSpan! as TextSpan).children!
        .cast<TextSpan>();
    expect(
      [
        for (var span in headingSpans)
          if (span.style?.backgroundColor != null) span.text,
      ].join(),
      'login',
    );

    // And a query nothing answers says so rather than showing an empty box.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No scenario matches “zzz”.'), findsOneWidget);
  });

  // The action refuses to overwrite, and the dialog stays open saying so —
  // the answer is another name typed into the field still on screen.
  testWidgets('a name whose file exists is reported in place', (tester) async {
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
    core.debugInstallRunner('.', _FakeRunner());
    var plugin = ScenariosPlugin(core);

    File('${root.path}/test/scenarios/taken_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// already here\n');

    await tester.runAsync(() async {
      core.track('.');
      while (core.scanResultFor('.') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    var address = ValueNotifier(
      Address(worktree: 'wt', plugin: scenariosPluginId),
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
    await tester.pump();

    await tester.tap(find.byTooltip('New scenario'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Taken');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('already exists'), findsOneWidget);
    // Still open, still on the untouched file, and the address never moved.
    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
    expect(
      File('${root.path}/test/scenarios/taken_test.dart').readAsStringSync(),
      '// already here\n',
    );
    expect(address.value.segments, isEmpty);
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
    double? captureScale,
    bool captureRaw = false,
  }) async {
    runs++;
    seenAxes.add(axes);
    Directory(outDir).createSync(recursive: true);
    Map<String, Object?> step(int index, String name, String text) {
      var png = '$outDir/$index-$name.png';
      File(png).writeAsBytesSync(_transparentPng);
      // A real tree file, as the harness writes one — the step page's
      // Elements tab reads it from disk.
      var tree = '$outDir/$index-$name.tree.json';
      File(tree).writeAsStringSync(
        jsonEncode({
          'root': {
            'id': '',
            'type': 'ShotRoot',
            'local': true,
            'children': [
              {
                'id': '0',
                'type': 'ChildBox',
                'local': true,
                'layout': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
              },
            ],
          },
        }),
      );
      return {
        'index': index,
        if (index > 0) 'parent': index - 1,
        'name': name,
        'auto': false,
        'image': png,
        'format': 'png',
        'width': 1,
        'height': 1,
        'tree': tree,
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
