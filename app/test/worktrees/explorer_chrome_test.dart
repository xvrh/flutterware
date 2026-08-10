import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:flutterware_app/src/worktrees/facts.dart';
import 'package:flutterware_app/src/worktrees/facts_controller.dart';
import 'package:flutterware_app/src/worktrees/facts_probe.dart';
import 'package:flutterware_app/src/worktrees/facts_store.dart';
import 'package:flutterware_app/src/worktrees/providers/agent.dart';
import 'package:flutterware_app/src/worktrees/providers/git.dart';

const _listing =
    'worktree /repo\nbranch refs/heads/main\n\n'
    'worktree /repo-explorer\nbranch refs/heads/feature/explorer\n';

/// A probe with no git, no `~/.claude` and no home directory behind it.
///
/// The store especially: the default writes to the developer's real
/// `~/.flutterware`, and opening a worktree records a clock — so a shell test
/// without this injected is a test that edits your home directory.
class _StubAgent implements AgentProbe {
  _StubAgent(this.waiting);

  final bool waiting;

  @override
  Future<AgentFacts?> probe(String worktreePath) async => AgentFacts(
    state: waiting && worktreePath == '/repo-explorer'
        ? AgentState.waiting
        : AgentState.none,
    title: 'Something being worked on',
    at: DateTime(2026, 8, 10, 14),
  );
}

/// A config that declares no plugins. The explorer is shell chrome and does not
/// go through one, which is the point — a closed worktree has no session at all.
class _StubLoader implements ManifestLoader {
  @override
  Future<PluginManifest?> load(String path) async => const PluginManifest([]);

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String path,
  ) async => (manifest: await load(path), error: null);

  @override
  String get dartExecutable => 'dart';

  @override
  Duration get timeout => Duration.zero;
}

late Directory _temp;

ShellController _controller({bool agentWaiting = false}) => ShellController(
  appContext: AppContext(logger: LogClient.print()),
  flutterSdk: FlutterSdkPath('/tmp/flutter'),
  registry: PluginRegistry(),
  coreRegistry: PluginCoreRegistry(),
  manifestLoader: _StubLoader(),
  discovery: WorktreeDiscovery(
    runProcess: (_, _, {workingDirectory}) async =>
        ProcessResult(0, 0, _listing, ''),
  ),
  worktreeFacts: (root) => WorktreeFactsController(
    repoRoot: root,
    probe: WorktreeFactsProbe(
      repoRoot: root,
      store: WorktreeFactsStore.open(
        root,
        at: File('${_temp.path}/worktrees.json'),
      ),
      agent: _StubAgent(agentWaiting),
      git: GitProbe(
        runProcess: (_, arguments, {workingDirectory}) async => ProcessResult(
          0,
          0,
          arguments.contains('status')
              ? '# branch.oid abc\n# branch.head feature/explorer\n'
              : '',
          '',
        ),
      ),
    ),
  ),
);

Future<ShellController> _pump(
  WidgetTester tester, {
  bool agentWaiting = false,
}) async {
  var shell = _controller(agentWaiting: agentWaiting);
  await shell.start('/repo');
  await tester.pumpWidget(ShellApp(shell));
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  setUp(() => _temp = Directory.systemTemp.createTempSync('fw-explorer-test'));
  tearDown(() => _temp.deleteSync(recursive: true));

  testWidgets('the explorer tab is pinned and cannot be closed', (
    tester,
  ) async {
    var shell = await _pump(tester);

    expect(find.byKey(explorerTabKey), findsOneWidget);
    // A worktree tab carries a close button; a pinned one must not, because
    // there is nothing to close and the band would be offering a dead control.
    expect(
      find.descendant(
        of: find.byKey(explorerTabKey),
        matching: find.byIcon(Icons.close),
      ),
      findsNothing,
    );
    expect(shell.isExplorer, isFalse, reason: 'the shell opens on a worktree');
  });

  testWidgets('it is a place, with an address', (tester) async {
    var shell = await _pump(tester);

    await tester.tap(find.byKey(explorerTabKey));
    await tester.pumpAndSettle();

    expect(shell.isExplorer, isTrue);
    expect(shell.address.toString(), 'fw:///worktrees');
    expect(find.text('Worktrees'), findsOneWidget);
  });

  testWidgets('every discovered worktree gets a row, open or not', (
    tester,
  ) async {
    var shell = await _pump(tester);
    await tester.tap(find.byKey(explorerTabKey));
    await tester.pumpAndSettle();

    // The whole point: `feature/explorer` has no tab and no session, and still
    // reports. A screen that only listed open worktrees would be the switcher.
    expect(find.text('main'), findsWidgets);
    expect(find.text('feature/explorer'), findsWidgets);
    expect(shell.isOpen(shell.worktrees.last), isFalse);
  });

  testWidgets('the plugin rail goes away, and comes back', (tester) async {
    var shell = await _pump(tester);
    expect(find.byKey(sidebarKey), findsOneWidget);

    await tester.tap(find.byKey(explorerTabKey));
    await tester.pumpAndSettle();
    // Nothing to list: the rail is this worktree's plugins and the explorer is
    // about all of them.
    expect(find.byKey(sidebarKey), findsNothing);
    // The window preference is untouched, so leaving restores it rather than
    // silently having turned it off.
    expect(shell.sidebarVisible, isTrue);

    // Back via the tab, which is the only way back there is: `selectHome` reads
    // the address's worktree and the explorer's address names none, so from
    // here it is a no-op. That is correct — "this worktree's home" is not a
    // place the explorer can be said to have.
    await tester.tap(find.byKey(worktreeTabKey(shell.worktrees.first)));
    await tester.pumpAndSettle();
    expect(shell.isExplorer, isFalse);
    expect(find.byKey(sidebarKey), findsOneWidget);
  });

  testWidgets('the badge counts only what will not progress without you', (
    tester,
  ) async {
    var quiet = await _pump(tester);
    await tester.tap(find.byKey(explorerTabKey));
    await tester.pumpAndSettle();
    expect(quiet.worktreeFacts!.needsYou, 0);

    await tester.pumpWidget(const SizedBox());
    var waiting = await _pump(tester, agentWaiting: true);
    await tester.tap(find.byKey(explorerTabKey));
    await tester.pumpAndSettle();

    expect(waiting.worktreeFacts!.needsYou, 1);
    expect(
      find.descendant(of: find.byKey(explorerTabKey), matching: find.text('1')),
      findsOneWidget,
    );
  });
}
