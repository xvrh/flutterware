import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

const _listing =
    'worktree /repo\nbranch refs/heads/main\n\n'
    'worktree /repo-explorer\nbranch refs/heads/feature/explorer\n';

const _manifestJson =
    '{"version":1,"plugins":['
    '{"id":"a.deps","label":"Dependencies"},'
    '{"id":"a.tests","label":"Tests"}]}';

class _Fake extends NativePlugin {
  _Fake(super.host, {this.status = Status.none, this.children = const []});

  final Status status;
  final List<PluginChild> children;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: status,
    children: children,
  );

  @override
  Widget buildPanel(BuildContext context, String? childId) =>
      Center(child: Text('panel:$id/${childId ?? '-'}'));
}

/// A panel that starts work on mount — the shape every real plugin has, and
/// the one that crashed the app: notifying from initState marks the shell's
/// AnimatedBuilder dirty during build.
class _EagerPanelPlugin extends NativePlugin {
  _EagerPanelPlugin(super.host);

  var tracked = false;

  void track() {
    tracked = true;
    notifyChanged();
  }

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: Status.neutral(tracked ? 'tracking' : '—'),
  );

  @override
  Widget buildPanel(BuildContext context, String? childId) => _EagerPanel(this);
}

class _EagerPanel extends StatefulWidget {
  const _EagerPanel(this.plugin);
  final _EagerPanelPlugin plugin;

  @override
  State<_EagerPanel> createState() => _EagerPanelState();
}

class _EagerPanelState extends State<_EagerPanel> {
  @override
  void initState() {
    super.initState();
    widget.plugin.track();
  }

  @override
  Widget build(BuildContext context) => const Text('eager');
}

class _StubLoader implements ManifestLoader {
  @override
  Future<PluginManifest?> load(String path) async =>
      PluginManifest.parse(_manifestJson);

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String path,
  ) async => (manifest: await load(path), error: null);

  @override
  String get dartExecutable => 'dart';
}

ShellController _controller() => ShellController(
  appContext: AppContext(logger: LogClient.print()),
  flutterSdk: FlutterSdkPath('/tmp/flutter'),
  registry: PluginRegistry({
    'a.deps': (h) => _Fake(h, status: const Status.neutral('170 direct')),
    'a.tests': (h) => _Fake(h, status: const Status.error('3 failing')),
  }),
  manifestLoader: _StubLoader(),
  discovery: WorktreeDiscovery(
    runProcess: (_, _, {workingDirectory}) async =>
        ProcessResult(0, 0, _listing, ''),
  ),
);

Future<ShellController> _pumpShell(WidgetTester tester) async {
  var shell = _controller();
  await shell.start('/repo');
  await tester.pumpWidget(ShellApp(shell));
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  testWidgets('renders a tab for the open worktree only', (tester) async {
    await _pumpShell(tester);

    expect(find.text('main'), findsOneWidget);
    // feature/explorer is discovered but not open, so it gets no tab.
    expect(find.text('feature/explorer'), findsNothing);
  });

  testWidgets('the sidebar shows each plugin with its status', (tester) async {
    await _pumpShell(tester);

    expect(find.text('Dependencies'), findsOneWidget);
    expect(find.text('Tests'), findsOneWidget);
    expect(find.text('170 direct'), findsOneWidget);
    expect(find.text('3 failing'), findsOneWidget);
  });

  testWidgets('mounts the selected plugin panel and switches', (tester) async {
    await _pumpShell(tester);

    expect(find.text('panel:a.deps/-'), findsOneWidget);
    expect(find.text('panel:a.tests/-'), findsNothing);

    await tester.tap(find.text('Tests'));
    await tester.pumpAndSettle();

    expect(find.text('panel:a.tests/-'), findsOneWidget);
    expect(find.text('panel:a.deps/-'), findsNothing);
  });

  testWidgets('the switcher lists worktrees that are not open', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('OPEN · 1'), findsOneWidget);
    expect(find.text('NOT OPEN · 1'), findsOneWidget);
    expect(find.text('feature/explorer'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('opening from the switcher adds a tab', (tester) async {
    var shell = await _pumpShell(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature/explorer'));
    await tester.pumpAndSettle();

    expect(shell.openWorktrees, hasLength(2));
    expect(find.text('feature/explorer'), findsOneWidget);
  });

  testWidgets('closing a tab removes it and releases the session', (
    tester,
  ) async {
    var shell = await _pumpShell(tester);
    await shell.open(shell.closedWorktrees.first);
    await tester.pumpAndSettle();
    expect(shell.openWorktrees, hasLength(2));

    // The second tab's close button.
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    expect(shell.openWorktrees, hasLength(1));
    expect(find.text('feature/explorer'), findsNothing);
  });

  group('children', () {
    ShellController childShell() => ShellController(
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/tmp/flutter'),
      registry: PluginRegistry({
        'a.deps': (h) => _Fake(
          h,
          status: const Status.neutral('2 packages'),
          children: const [
            PluginChild(id: 'app', label: 'app', status: Status.neutral('58')),
            PluginChild(id: 'ui', label: 'ui', status: Status.error('failed')),
          ],
        ),
        'a.tests': _Fake.new,
      }),
      manifestLoader: _StubLoader(),
      discovery: WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 0, _listing, ''),
      ),
    );

    testWidgets('expands under the selected plugin only', (tester) async {
      var shell = childShell();
      await shell.start('/repo');
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();

      // a.deps is selected by default, so its children show with their status.
      expect(find.text('app'), findsOneWidget);
      expect(find.text('58'), findsOneWidget);
      expect(find.text('failed'), findsOneWidget);

      // Selecting the other plugin collapses them.
      await tester.tap(find.text('Tests'));
      await tester.pumpAndSettle();
      expect(find.text('app'), findsNothing);
    });

    testWidgets('the first child is selected with its plugin', (tester) async {
      var shell = childShell();
      await shell.start('/repo');
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();

      expect(shell.selectedChildId, 'app');
      expect(find.text('panel:a.deps/app'), findsOneWidget);
    });

    testWidgets('selecting a child switches the panel', (tester) async {
      var shell = childShell();
      await shell.start('/repo');
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ui'));
      await tester.pumpAndSettle();

      expect(shell.selectedChildId, 'ui');
      expect(find.text('panel:a.deps/ui'), findsOneWidget);
    });
  });

  testWidgets('a panel may start work in initState without crashing', (
    tester,
  ) async {
    var shell = ShellController(
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/tmp/flutter'),
      registry: PluginRegistry({'a.deps': _EagerPanelPlugin.new}),
      manifestLoader: _StubLoader(),
      discovery: WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 0, _listing, ''),
      ),
    );
    await shell.start('/repo');
    await tester.pumpWidget(ShellApp(shell));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('eager'), findsOneWidget);
    // The deferred notification still lands.
    expect(find.text('tracking'), findsOneWidget);
  });

  testWidgets('a worktree with no plugins explains itself', (tester) async {
    var shell = ShellController(
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/tmp/flutter'),
      registry: PluginRegistry(),
      manifestLoader: _EmptyLoader(),
      discovery: WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 0, _listing, ''),
      ),
    );
    await shell.start('/repo');
    await tester.pumpWidget(ShellApp(shell));
    await tester.pumpAndSettle();

    expect(find.textContaining('No plugins declared'), findsOneWidget);
  });
}

class _EmptyLoader implements ManifestLoader {
  @override
  Future<PluginManifest?> load(String path) async => null;

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String path,
  ) async => (manifest: null, error: null);

  @override
  String get dartExecutable => 'dart';
}
