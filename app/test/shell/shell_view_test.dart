import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/shell_search.dart';
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:flutterware_app/src/ui/command_palette.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

const _listing =
    'worktree /repo\nbranch refs/heads/main\n\n'
    'worktree /repo-explorer\nbranch refs/heads/feature/explorer\n';

const _manifestJson =
    '{"version":1,"plugins":['
    '{"id":"a.deps","label":"Dependencies"},'
    '{"id":"a.tests","label":"Tests"}]}';

class _FakeCore extends PluginCore {
  _FakeCore(super.host, {this.status = Status.none, this.children = const []});

  final Status status;
  final List<PluginChild> children;

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: status,
    children: children,
  );
}

class _Fake extends NativePlugin<_FakeCore> {
  _Fake(super.core);

  /// Reports every segment it was given, so a test can see what survived the
  /// trip from the address to the panel — which is exactly what used to be
  /// truncated to one.
  @override
  Widget buildPanel(BuildContext context) {
    var segments = AddressScope.segments(context);
    return Center(
      child: Text('panel:$id/${segments.isEmpty ? '-' : segments.join('/')}'),
    );
  }
}

/// A core whose panel starts work on mount — the shape every real plugin has,
/// and the one that crashed the app: notifying from initState marks the shell's
/// AnimatedBuilder dirty during build.
class _EagerCore extends PluginCore {
  _EagerCore(super.host);

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
}

class _EagerPanelPlugin extends NativePlugin<_EagerCore> {
  _EagerPanelPlugin(super.core);

  @override
  Widget buildPanel(BuildContext context) => _EagerPanel(this);
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
    widget.plugin.core.track();
  }

  @override
  Widget build(BuildContext context) => const Text('eager');
}

PluginRegistry _panels(Iterable<String> ids) =>
    PluginRegistry({for (var id in ids) id: panelFor<_FakeCore>(_Fake.new)});

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

ShellController _controller({String listing = _listing}) => ShellController(
  appContext: AppContext(logger: LogClient.print()),
  flutterSdk: FlutterSdkPath('/tmp/flutter'),
  registry: _panels(const ['a.deps', 'a.tests']),
  coreRegistry: PluginCoreRegistry({
    'a.deps': (h) => _FakeCore(h, status: const Status.neutral('170 direct')),
    'a.tests': (h) => _FakeCore(h, status: const Status.error('3 failing')),
  }),
  manifestLoader: _StubLoader(),
  discovery: WorktreeDiscovery(
    runProcess: (_, _, {workingDirectory}) async =>
        ProcessResult(0, 0, listing, ''),
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
    var shell = await _pumpShell(tester);

    expect(find.byKey(worktreeTabKey(shell.worktrees.first)), findsOneWidget);
    // feature/explorer is discovered but not open, so it gets no tab.
    expect(find.byKey(worktreeTabKey(shell.worktrees.last)), findsNothing);
  });

  testWidgets('a worktree opens on its home screen', (tester) async {
    await _pumpShell(tester);

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('main checkout'), findsOneWidget);
    // No plugin panel is mounted until you pick one.
    expect(find.textContaining('panel:'), findsNothing);
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

    await tester.tap(find.text('Dependencies'));
    await tester.pumpAndSettle();

    expect(find.text('panel:a.deps/-'), findsOneWidget);
    expect(find.text('panel:a.tests/-'), findsNothing);

    await tester.tap(find.text('Tests'));
    await tester.pumpAndSettle();

    expect(find.text('panel:a.tests/-'), findsOneWidget);
    expect(find.text('panel:a.deps/-'), findsNothing);
  });

  testWidgets('a panel is given every segment below the plugin', (
    tester,
  ) async {
    // The bug this contract was widened for: an address naming a package *and*
    // an entry used to reach the panel as the package alone, so a search hit
    // opened the right plugin showing the wrong thing.
    var shell = await _pumpShell(tester);

    shell.go(
      Address(
        worktree: '~',
        plugin: 'a.deps',
        segments: ['app', 'demo/avatar.dart#members'],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('panel:a.deps/app/demo/avatar.dart#members'),
      findsOneWidget,
    );
  });

  testWidgets('moving within a plugin does not remount its panel', (
    tester,
  ) async {
    // A compile loop lives in the panel's plugin; remounting for a click in its
    // own tree would tear one down and start another.
    var shell = await _pumpShell(tester);
    shell.selectChild('a.deps', 'app');
    await tester.pumpAndSettle();
    var before = tester.state(find.byType(Scaffold));

    shell.selectChild('a.deps', 'examples/example');
    await tester.pumpAndSettle();

    expect(find.text('panel:a.deps/examples/example'), findsOneWidget);
    expect(tester.state(find.byType(Scaffold)), same(before));
  });

  testWidgets('the switcher lists worktrees that are not open', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byTooltip('Switch worktree'));
    await tester.pumpAndSettle();

    expect(find.text('OPEN · 1'), findsOneWidget);
    expect(find.text('NOT OPEN · 1'), findsOneWidget);
    expect(find.text('feature/explorer'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('opening from the switcher adds a tab', (tester) async {
    var shell = await _pumpShell(tester);

    await tester.tap(find.byTooltip('Switch worktree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature/explorer'));
    await tester.pumpAndSettle();

    expect(shell.openWorktrees, hasLength(2));
    expect(find.byKey(worktreeTabKey(shell.worktrees.last)), findsOneWidget);
  });

  testWidgets('closing a tab removes it and releases the session', (
    tester,
  ) async {
    var shell = await _pumpShell(tester);
    await shell.open(shell.closedWorktrees.first);
    await tester.pumpAndSettle();
    expect(shell.openWorktrees, hasLength(2));

    // The second tab's close button. Scrolled to first: the tab strip is a
    // horizontal ListView by design, and at the 800px test surface a second
    // tab no longer fits beside the rest of the band.
    var close = find.byIcon(Icons.close).last;
    await tester.ensureVisible(close);
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(shell.openWorktrees, hasLength(1));
    expect(find.byKey(worktreeTabKey(shell.worktrees.last)), findsNothing);
  });

  group('children', () {
    ShellController childShell() => ShellController(
      appContext: AppContext(logger: LogClient.print()),
      flutterSdk: FlutterSdkPath('/tmp/flutter'),
      registry: _panels(const ['a.deps', 'a.tests']),
      coreRegistry: PluginCoreRegistry({
        'a.deps': (h) => _FakeCore(
          h,
          status: const Status.neutral('2 packages'),
          children: const [
            PluginChild(id: 'app', label: 'app', status: Status.neutral('58')),
            PluginChild(id: 'ui', label: 'ui', status: Status.error('failed')),
          ],
        ),
        'a.tests': _FakeCore.new,
      }),
      manifestLoader: _StubLoader(),
      discovery: WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 0, _listing, ''),
      ),
    );

    testWidgets('a long status cannot squeeze out the name', (tester) async {
      var shell = ShellController(
        appContext: AppContext(logger: LogClient.print()),
        flutterSdk: FlutterSdkPath('/tmp/flutter'),
        registry: _panels(const ['a.deps', 'a.tests']),
        coreRegistry: PluginCoreRegistry({
          'a.deps': (h) => _FakeCore(
            h,
            children: const [
              PluginChild(
                id: 'examples/example',
                label: 'examples/example',
                status: Status.warn('10 assets · 347 kB · 2 problems'),
              ),
            ],
          ),
          'a.tests': _FakeCore.new,
        }),
        manifestLoader: _StubLoader(),
        discovery: WorktreeDiscovery(
          runProcess: (_, _, {workingDirectory}) async =>
              ProcessResult(0, 0, _listing, ''),
        ),
      );
      await shell.start('/repo');
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dependencies'));
      await tester.pumpAndSettle();

      // The row used to give the status all the width it asked for, leaving
      // the `Expanded` label at zero — a row that says how much and not *what*.
      var label = find.descendant(
        of: find.byKey(sidebarKey),
        matching: find.text('examples/example'),
      );
      expect(label, findsOneWidget);
      expect(tester.getSize(label).width, greaterThan(0));
    });

    testWidgets('expands under the selected plugin only', (tester) async {
      var shell = childShell();
      await shell.start('/repo');
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dependencies'));
      await tester.pumpAndSettle();

      // Children show only under the selected plugin, with their status.
      // Scoped to the rail: `app` is also a segment of the address, which the
      // bar along the bottom now spells out.
      var inRail = find.descendant(
        of: find.byKey(sidebarKey),
        matching: find.text('app'),
      );
      expect(inRail, findsOneWidget);
      expect(find.text('58'), findsOneWidget);
      expect(find.text('failed'), findsOneWidget);

      // Selecting the other plugin collapses them.
      await tester.tap(find.text('Tests'));
      await tester.pumpAndSettle();
      expect(inRail, findsNothing);
    });

    testWidgets('the first child is selected with its plugin', (tester) async {
      var shell = childShell();
      await shell.start('/repo');
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dependencies'));
      await tester.pumpAndSettle();

      expect(shell.selectedChildId, 'app');
      expect(find.text('panel:a.deps/app'), findsOneWidget);
    });

    testWidgets('selecting a child switches the panel', (tester) async {
      var shell = childShell();
      await shell.start('/repo');
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dependencies'));
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
      registry: PluginRegistry({
        'a.deps': panelFor<_EagerCore>(_EagerPanelPlugin.new),
      }),
      coreRegistry: PluginCoreRegistry({'a.deps': _EagerCore.new}),
      manifestLoader: _StubLoader(),
      discovery: WorktreeDiscovery(
        runProcess: (_, _, {workingDirectory}) async =>
            ProcessResult(0, 0, _listing, ''),
      ),
    );
    await shell.start('/repo');
    await tester.pumpWidget(ShellApp(shell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dependencies'));
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

  testWidgets('a long worktree name does not stretch its tab', (tester) async {
    // A tab wide enough to hold the whole name is a tab wide enough to push
    // the switcher off screen; the tooltip is where the full name lives.
    var shell = _controller(
      listing:
          'worktree /repo/a-very-long-worktree-name-that-keeps-going-and-going\n'
          'branch refs/heads/main\n\n',
    );
    await shell.start(
      '/repo/a-very-long-worktree-name-that-keeps-going-and-going',
    );
    await tester.pumpWidget(ShellApp(shell));
    await tester.pumpAndSettle();

    var label = find.descendant(
      of: find.byKey(worktreeTabKey(shell.worktrees.first)),
      matching: find.byType(Text),
    );
    expect(tester.getSize(label.first).width, lessThanOrEqualTo(180));
  });

  testWidgets('clickable rows take the pointer cursor', (tester) async {
    await _pumpShell(tester);

    var mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await tester.pump();

    await mouse.moveTo(tester.getCenter(find.text('Overview')));
    await tester.pump();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
      reason: 'a row that does not answer the mouse reads as decoration',
    );
  });

  testWidgets('the sidebar can be hidden and brought back', (tester) async {
    await _pumpShell(tester);
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.byTooltip(RegExp('Hide the sidebar')));
    await tester.pumpAndSettle();
    expect(
      find.text('Overview'),
      findsNothing,
      reason: 'the rail goes to nothing, not to a strip',
    );

    await tester.tap(find.byTooltip(RegExp('Show the sidebar')));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);
  });

  testWidgets('cmd+B works without clicking the window first', (tester) async {
    // The binding existed but nothing in the shell held focus, so key events
    // went to the root scope — an ancestor of the shortcuts, never a
    // descendant — and no binding was reached until something was clicked.
    await _pumpShell(tester);
    expect(find.text('Overview'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsNothing);
  });

  group('search', () {
    /// Scoped to the palette: the sidebar shows the same plugin names, so an
    /// unscoped finder would pass whether the palette opened or not.
    Finder inPalette(String text) => find.descendant(
      of: find.byType(CommandPalette),
      matching: find.text(text, findRichText: true),
    );

    testWidgets('the trigger opens it', (tester) async {
      await _pumpShell(tester);
      expect(find.byType(CommandPalette), findsNothing);

      await tester.tap(find.byType(SearchTrigger));
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsOneWidget);
      expect(inPalette('Type to search'), findsOneWidget);
    });

    testWidgets('cmd+K opens it', (tester) async {
      await _pumpShell(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsOneWidget);
    });

    testWidgets('typing finds a plugin by name', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byType(SearchTrigger));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'depend');
      await tester.pumpAndSettle();

      expect(inPalette('Dependencies'), findsOneWidget);
      expect(
        inPalette('Tests'),
        findsNothing,
        reason: 'the query filters; it does not just list everything',
      );
    });

    testWidgets('a hit navigates to its plugin and closes', (tester) async {
      await _pumpShell(tester);
      expect(find.text('panel:a.deps/-'), findsNothing);

      await tester.tap(find.byType(SearchTrigger));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'depend');
      await tester.pumpAndSettle();

      await tester.tap(inPalette('Dependencies'));
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsNothing);
      expect(
        find.text('panel:a.deps/-'),
        findsOneWidget,
        reason: 'the address is the instruction — it selected the plugin',
      );
    });

    testWidgets('escape closes without navigating', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byType(SearchTrigger));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsNothing);
      expect(find.text('panel:a.deps/-'), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
    });

    testWidgets('a query that matches nothing says so', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byType(SearchTrigger));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(inPalette('No results for “zzzz”'), findsOneWidget);
    });
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
