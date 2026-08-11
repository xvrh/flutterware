import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/dev_stack/stack_block.dart';
import 'package:flutterware_app/src/plugins/native/dev_stack_core.dart';
import 'package:flutterware_app/src/plugins/native/dev_stack_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/ui/action_button.dart';
import 'package:flutterware_app/src/ui/theme.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';

/// The block's layout rules, as behaviour.
///
/// See `docs/superpowers/specs/2026-08-11-dev-stack-ui-study.md`. What is
/// asserted here is the handful of rules that were *decided* rather than drawn:
/// which slot a failure lands in, when a control is emphatic, what the compact
/// form is allowed to drop, and what a cold start says when it has a cache.
/// Colours and gaps are not asserted — a test that pins those only makes the
/// next visual change expensive.
void main() {
  late Directory runDir;
  late Directory project;
  late Completer<ProcessResult>? held;

  DevStackPlugin pluginWith(
    Map<String, Object?> config, {
    required String probeOutput,
    int exitCode = 0,
  }) {
    var core =
        DevStackCore(
            PluginHost(
              id: devStackPluginId,
              label: 'Example server',
              worktree: Worktree(path: project.path),
              workspace: Workspace(
                root: project.path,
                declared: [],
                discovered: [],
                appContext: AppContext(logger: LogClient.print()),
                flutterSdk: FlutterSdkPath('/tmp/flutter'),
              ),
              config: config,
            ),
          )
          ..runProcess = (command, {workingDirectory}) async {
            if (held case var completer?) return completer.future;
            return ProcessResult(0, exitCode, probeOutput, '');
          };
    return DevStackPlugin(core);
  }

  Map<String, Object?> jsonConfig() => DevStack.background(
    probe: Probe.json(['stack', 'doctor']),
    start: ['stack', 'up'],
    stop: ['stack', 'down'],
    commands: [
      const StackCommand('logs', 'Logs', ['stack', 'logs']),
    ],
  ).config;

  Future<void> pump(
    WidgetTester tester,
    DevStackPlugin plugin, {
    bool compact = false,
    VoidCallback? onOpenPanel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: DevStackBlock(
              plugin,
              compact: compact,
              onOpenPanel: onOpenPanel,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    runDir = Directory.systemTemp.createTempSync('fw-stack-block-run-');
    project = Directory.systemTemp.createTempSync('fw-stack-block-');
    held = null;
    DevStackCore.runDirProvider = () => runDir.path;
  });

  tearDown(() {
    DevStackCore.runDirProvider = flutterwareRunDir;
    for (var dir in [runDir, project]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  testWidgets('the state is a word, and the address is under it', (
    tester,
  ) async {
    var plugin = pluginWith(
      jsonConfig(),
      probeOutput: '{"state":"up","detail":"localhost:8080 · pid 493"}',
    );
    await pump(tester, plugin);
    expect(find.text('up'), findsOneWidget);
    expect(find.text('localhost:8080 · pid 493'), findsOneWidget);
    // Not `up · localhost:8080 · pid 493 · just now` — the age labels the block
    // from the section line above rather than joining the state in a run-on.
    expect(find.textContaining('· just now'), findsNothing);
    plugin.core.dispose();
  });

  testWidgets('the home screen keeps the services', (tester) async {
    // The compact form used to drop them, which left the one screen you glance
    // at unable to say *what* was up.
    var plugin = pluginWith(
      jsonConfig(),
      probeOutput:
          '{"state":"up","services":['
          '{"name":"postgres","port":8200,"state":"up"},'
          '{"name":"identity","port":8201,"state":"up"}]}',
    );
    await pump(tester, plugin, compact: true);
    expect(find.text('postgres :8200'), findsOneWidget);
    expect(find.text('identity :8201'), findsOneWidget);
    plugin.core.dispose();
  });

  testWidgets('a stack that is up but not all of it says how much', (
    tester,
  ) async {
    var plugin = pluginWith(
      jsonConfig(),
      probeOutput:
          '{"state":"up","services":['
          '{"name":"postgres","port":8200,"state":"up"},'
          '{"name":"sync","port":8202,"state":"starting"}]}',
    );
    await pump(tester, plugin);
    expect(find.text('up, 1 of 2'), findsOneWidget);
    plugin.core.dispose();
  });

  testWidgets('a failed probe puts the reason where the address was', (
    tester,
  ) async {
    var plugin = pluginWith(
      jsonConfig(),
      probeOutput: 'Cannot connect to the Docker daemon.',
      exitCode: 1,
    );
    await pump(tester, plugin);
    expect(find.text("can't tell"), findsOneWidget);
    expect(find.text('Cannot connect to the Docker daemon.'), findsOneWidget);
    // Re-reading is the next move when the reading is the broken thing, so the
    // link becomes Check now even though this stack declares a Logs command.
    expect(find.text('Check now'), findsOneWidget);
    expect(find.text('Logs'), findsNothing);
    plugin.core.dispose();
  });

  testWidgets('only a stack known to be down gets an emphatic Bring up', (
    tester,
  ) async {
    var down = pluginWith(jsonConfig(), probeOutput: '{"state":"down"}');
    await pump(tester, down);
    expect(
      tester
          .widget<FwActionButton>(
            find.widgetWithText(FwActionButton, 'Bring up'),
          )
          .primary,
      isTrue,
    );
    down.core.dispose();

    // After a failed probe the same control is offered — trying is the useful
    // move — but quietly, because nothing has established that it will work.
    var broken = pluginWith(jsonConfig(), probeOutput: 'nope', exitCode: 1);
    await pump(tester, broken);
    expect(
      tester
          .widget<FwActionButton>(
            find.widgetWithText(FwActionButton, 'Bring up'),
          )
          .primary,
      isFalse,
    );
    broken.core.dispose();
  });

  testWidgets('an observe-only stack gets a state and no controls', (
    tester,
  ) async {
    var plugin = pluginWith(
      DevStack.background(probe: Probe.json(['stack', 'doctor'])).config,
      probeOutput: '{"state":"up","detail":"shared, not ours"}',
    );
    await pump(tester, plugin);
    expect(find.text('up'), findsOneWidget);
    expect(find.byType(FwActionButton), findsNothing);
    plugin.core.dispose();
  });

  testWidgets('a transition names itself and shows how long it has been', (
    tester,
  ) async {
    var plugin = pluginWith(jsonConfig(), probeOutput: '{"state":"down"}');
    await pump(tester, plugin);
    held = Completer<ProcessResult>();
    unawaited(plugin.core.start());
    // Two frames, not : a core's change notification is
    // coalesced through a microtask and a stream before it reaches the widget,
    // and a transition never settles by design — the bar animates and the
    // elapsed clock schedules a frame a second until the command returns.
    await tester.pump();
    await tester.pump();

    expect(find.text('bringing up'), findsOneWidget);
    expect(find.text('0s elapsed'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FwActionButton>(
            find.widgetWithText(FwActionButton, 'Bringing up'),
          )
          .onPressed,
      isNull,
    );

    held!.complete(ProcessResult(0, 0, '', ''));
    held = null;
    await tester.pumpAndSettle();
    plugin.core.dispose();
  });

  testWidgets('a cold start says what it last saw, not "not checked"', (
    tester,
  ) async {
    // Write a reading, age it on disk, then open a fresh core over the same
    // worktree with its probe held. What is on screen is then exactly the cold
    // open: a cache, and a first check still in flight.
    var first = pluginWith(jsonConfig(), probeOutput: '{"state":"up"}');
    await first.core.refresh();
    first.core.dispose();

    var cache = runDir.listSync().whereType<File>().firstWhere(
      (f) => f.path.contains('stack-'),
    );
    var json = jsonDecode(cache.readAsStringSync()) as Map<String, Object?>;
    json['checkedAt'] = DateTime.now()
        .subtract(const Duration(hours: 2))
        .toIso8601String();
    cache.writeAsStringSync(jsonEncode(json));

    held = Completer<ProcessResult>();
    var second = pluginWith(jsonConfig(), probeOutput: '{"state":"up"}');
    await pump(tester, second);

    expect(find.textContaining('last seen 2h ago'), findsOneWidget);
    // The reading is history until the probe confirms it, so nothing offers to
    // act on it yet.
    expect(
      tester.widget<FwActionButton>(find.byType(FwActionButton)).onPressed,
      isNull,
    );

    held!.complete(ProcessResult(0, 0, '{"state":"up"}', ''));
    held = null;
    await tester.pumpAndSettle();
    second.core.dispose();
  });

  testWidgets('the way into the panel is offered on the home screen only', (
    tester,
  ) async {
    var opened = 0;
    var plugin = pluginWith(jsonConfig(), probeOutput: '{"state":"up"}');
    await pump(tester, plugin, compact: true, onOpenPanel: () => opened++);
    await tester.tap(find.text('Open panel →'));
    expect(opened, 1);
    plugin.core.dispose();

    var inPanel = pluginWith(jsonConfig(), probeOutput: '{"state":"up"}');
    await pump(tester, inPanel, onOpenPanel: () => opened++);
    expect(find.text('Open panel →'), findsNothing);
    inPanel.core.dispose();
  });
}
