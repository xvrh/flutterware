import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/framed_shot.dart';
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

    // The Semantics tab: the reader's words, with the role badged and the
    // actions listed, read from the file the fake wrote.
    await tester.tap(find.text('Semantics'));
    await tester.pump();
    expect(find.text('"Add to cart"'), findsOneWidget);
    expect(find.text('button'), findsOneWidget);
    expect(find.text('tap'), findsOneWidget);

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

  testWidgets('records the motion of every transition, and can be told not '
      'to', (tester) async {
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

    // On by default: a recording you have to ask for is one nobody finds.
    expect(
      runner.seenRecordIntervals.single,
      ScenariosCore.panelMotionInterval,
    );

    // Hovering the node plays the transition into it, in place: the shot is
    // swapped for a frame, and the device body and its size do not move.
    var shot = find.byType(FramedShot).first;
    expect(tester.widget<FramedShot>(shot).image, isNull);
    var pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer();
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.text('1 · end')));
    await tester.pump();

    var playing = find.byWidgetPredicate(
      (w) => w is FramedShot && w.image != null,
    );
    expect(playing, findsOneWidget);

    // And leaving parks it back on the still, so the canvas goes back to
    // being a wall of screenshots.
    await pointer.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(playing, findsNothing);

    // The step page gets the transport under the frame: the recording is 4
    // frames of 33ms, so three intervals of motion.
    await tester.tap(find.text('1 · end'), warnIfMissed: false);
    await tester.pump();
    // Parked at the end, which is the step's own screenshot — so arriving on
    // the page looks exactly as it did before any of this existed.
    expect(find.text('99 / 99 ms'), findsOneWidget);
    expect(find.text('4 frames'), findsOneWidget);

    // Stepping back moves the clock, not just the picture.
    await tester.tap(find.byTooltip('Previous frame'));
    await tester.pump();
    expect(find.text('66 / 99 ms'), findsOneWidget);

    // The first step is a `pumpWidget` the fake recorded nothing for, so its
    // page has no transport at all rather than an empty one.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.tap(find.text('0 · shot'), warnIfMissed: false);
    await tester.pump();
    expect(find.textContaining(' ms'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    // Turned off in the run menu, the next run asks for nothing — and the
    // step page goes back to being the still it was.
    await tester.tap(find.byTooltip('More run options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Record motion'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
    expect(runner.seenRecordIntervals.last, isNull);
    await tester.tap(find.text('1 · end'), warnIfMissed: false);
    await tester.pump();
    expect(find.textContaining(' ms'), findsNothing);
  });

  testWidgets('an unset device is left for the folder to answer, and the '
      'chip says what it answered', (tester) async {
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
    // Nothing chosen, so nothing is sent — only the fallback the host would
    // like used where a folder declares no profile.
    expect(runner.seenAxes.single.device, isNull);
    expect(runner.seenUnspecified.single, 'iphone-13');
    // And the chip reports what the run came back as, marked as not the
    // reader's own choice.
    expect(find.text('iPhone 13 (default)'), findsOneWidget);
  });

  testWidgets('a device is remembered per pool, so a desktop scenario is '
      'never opened on the phone the last one used', (tester) async {
    // Two folders, each with a `flutter_test_config.dart` — which is all the
    // panel needs to tell two pools apart. What the configs *say* lives in
    // the guest; the folder is the identity.
    for (var folder in ['mobile', 'desktop']) {
      var directory = Directory(p.join(root.path, 'test', 'scenarios', folder))
        ..createSync(recursive: true);
      File(
        p.join(directory.path, 'flutter_test_config.dart'),
      ).writeAsStringSync('// this folder is a pool');
    }

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
        segments: ['.', 'test', 'scenarios', 'mobile', 'shop_test.dart', 'A'],
        axes: {'device': 'iphone-13'},
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
    // The list pane spins while the scan runs, so this pumps a fixed number
    // of frames rather than settling.
    Future<void> pumpFrames() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await pumpFrames();
    // A pasted link is honoured as it stands: the first pool adopts it.
    expect(address.value.axes['device'], 'iphone-13');
    expect(runner.seenAxes.last.device, 'iphone-13');

    // Crossing into the other pool drops the phone rather than carrying it —
    // this is the overflow the memory exists to prevent.
    address.value = address.value.copyWith(
      segments: ['.', 'test', 'scenarios', 'desktop', 'window_test.dart', 'A'],
    );
    await pumpFrames();
    expect(address.value.axes.containsKey('device'), isFalse);
    expect(runner.seenAxes.last.device, isNull);

    // Picking one here belongs to *this* pool — the device chip writes the
    // address, which is all a pick is.
    address.value = address.value.copyWith(axes: {'device': 'macbook-pro'});
    await pumpFrames();
    expect(runner.seenAxes.last.device, 'macbook-pro');

    // ...and going back restores the phone, not the laptop.
    address.value = address.value.copyWith(
      segments: ['.', 'test', 'scenarios', 'mobile', 'shop_test.dart', 'A'],
    );
    await pumpFrames();
    expect(address.value.axes['device'], 'iphone-13');

    // Then forward again, to the laptop this pool last used.
    address.value = address.value.copyWith(
      segments: ['.', 'test', 'scenarios', 'desktop', 'window_test.dart', 'A'],
    );
    await pumpFrames();
    expect(address.value.axes['device'], 'macbook-pro');
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

    // The 240px list says the short half — which directory is empty, and the
    // button that fills it.
    expect(find.text('No scenarios under test/.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New scenario'), findsWidgets);

    // The long half is the help page, in the detail pane where a code example
    // has the width to be code.
    expect(find.text('How to write a scenario'), findsOneWidget);
    expect(
      find.textContaining(
        "import 'package:flutterware/flutter_test.dart'",
        findRichText: true,
      ),
      findsWidgets,
    );
    expect(
      find.textContaining('fw run scenarios new', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('the help page is still reachable once scenarios exist', (
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
    var plugin = ScenariosPlugin(core);

    File('${root.path}/test/scenarios/a_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync("void main() { scenario('A', (s) async {}); }\n");

    await tester.runAsync(() async {
      core.track('.');
      while (core.scanResultFor('.') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    var address = ValueNotifier(
      Address(worktree: 'wt', plugin: scenariosPluginId, segments: ['.']),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        // A populated pane draws the filter, which is a `TextField` and wants
        // the Material the shell puts under every panel.
        home: Scaffold(
          body: AddressRoot(
            address: address,
            onChanged: (a) => address.value = a,
            child: Builder(builder: plugin.buildPanel),
          ),
        ),
      ),
    );
    await tester.pump();

    // A suite that exists is not a suite whose author knows the API by heart:
    // the door is in the header, above every state.
    expect(find.text('How to write a scenario'), findsNothing);
    await tester.tap(find.byTooltip('How to write a scenario'));
    await tester.pump();

    expect(address.value.segments, ['.', 'help']);
    expect(find.text('How to write a scenario'), findsOneWidget);
    // The list is still there beside it — help is a page, not a mode.
    expect(find.text('A'), findsOneWidget);
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

    // Every door: the pane's persistent header, the empty list's call to
    // action, and the help page's — which is the detail pane while there are
    // none. The list's is the one tapped, tree order putting it first.
    expect(find.byTooltip('New scenario'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New scenario'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, 'New scenario').first);
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

  // The labels drop what every file shares — computed from the files, so a
  // suite spread across test/ shows the part that differs and the header
  // names the directory they all sit under.
  testWidgets('a spread suite is labelled by what differs', (tester) async {
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

    File('${root.path}/test/scenarios/checkout_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync("void main() => scenario('Pays', () {});\n");
    File('${root.path}/test/widgets/menu_test.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync("void main() => scenario('Opens', () {});\n");

    await tester.runAsync(() async {
      core.track('.');
      while (core.scanResultFor('.') == null) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
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

    expect(find.text('test'), findsOneWidget);
    expect(
      find.text('scenarios/checkout_test.dart', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('widgets/menu_test.dart', findRichText: true),
      findsOneWidget,
    );
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
  final seenUnspecified = <String?>[];
  final seenRecordIntervals = <Duration?>[];

  /// What the harness reports it resolved an unnamed device to. The real one
  /// asks the folder's profile first; this one just echoes the fallback.
  String? resolvedDevice;

  @override
  Future<Map<String, Object?>> run({
    required String outDir,
    String? file,
    String? scenario,
    String? tag,
    ScenarioAxes axes = const ScenarioAxes(),
    String? unspecifiedDevice,
    double? captureScale,
    bool captureRaw = false,
    bool captureNative = false,
    Duration? recordInterval,
    double? recordScale,
    int recordMaxFrames = 90,
    DateTime? clock,
  }) async {
    runs++;
    seenAxes.add(axes);
    seenUnspecified.add(unspecifiedDevice);
    seenRecordIntervals.add(recordInterval);
    resolvedDevice = axes.device ?? unspecifiedDevice;
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
      // And a semantics file — the Semantics tab reads it from disk.
      var semantics = '$outDir/$index-$name.semantics.json';
      File(semantics).writeAsStringSync(
        jsonEncode({
          'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
          'children': [
            {
              'rect': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
              'label': 'Add to cart',
              'flags': ['isButton'],
              'actions': ['tap'],
              'children': <Object?>[],
            },
          ],
        }),
      );
      // A recorded transition, when the run asked for one: a directory of
      // numbered frames, as the harness writes them.
      String? frames;
      var intervalMs = recordInterval?.inMilliseconds;
      if (intervalMs != null && index > 0) {
        var directory = Directory('$outDir/$index-$name.frames')
          ..createSync(recursive: true);
        for (var frame = 0; frame < 4; frame++) {
          File(
            '${directory.path}/${frame.toString().padLeft(4, '0')}.png',
          ).writeAsBytesSync(_transparentPng);
        }
        frames = directory.path;
      }
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
        'semantics': semantics,
        'texts': [text],
        // Every real step names the verb that produced it, and the arrow into
        // it is drawn from that.
        if (index > 0) ...{'verb': 'tap', 'target': '"Buy"'},
        if (frames != null) ...{
          'frames': frames,
          'frameCount': 4,
          'frameWidth': 1,
          'frameHeight': 1,
          'frameIntervalMs': intervalMs,
        },
      };
    }

    return {
      'ms': 5,
      'scenarios': [
        {
          'file': file,
          'name': scenario,
          'device': resolvedDevice,
          'ok': true,
          'ms': 3,
          'steps': [step(0, 'shot', 'hello'), step(1, 'end', 'bye')],
        },
      ],
    };
  }

  /// Nothing to list, and nothing spawned to find out: the panel asks for a
  /// listing the moment a scenario is open, and the base implementation would
  /// try to compile a harness against a Flutter SDK that is not there.
  @override
  Future<List<ScenarioListing>> list() async => const [];

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
