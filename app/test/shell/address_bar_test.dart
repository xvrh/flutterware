import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/logs/remote_log_client.dart';
import 'package:flutterware_app/src/address/address_scope.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/manifest_loader.dart';
import 'package:flutterware_app/src/plugins/native_plugin.dart';
import 'package:flutterware_app/src/plugins/plugin_core.dart';
import 'package:flutterware_app/src/plugins/registry.dart';
import 'package:flutterware_app/src/shell/address_bar.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:flutterware_app/src/shell/worktree_discovery.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';

const _listing =
    'worktree /repo\nbranch refs/heads/main\n\n'
    'worktree /repo-explorer\nbranch refs/heads/feature/explorer\n';

class _FakeCore extends PluginCore {
  _FakeCore(super.host);

  @override
  PluginReport get report => PluginReport(id: host.id, label: host.label);
}

class _Fake extends NativePlugin<_FakeCore> {
  _Fake(super.core);

  @override
  Widget buildPanel(BuildContext context) {
    var segments = AddressScope.segments(context);
    return Center(
      child: Text('panel:$id/${segments.isEmpty ? '-' : segments.join('/')}'),
    );
  }
}

class _StubLoader implements ManifestLoader {
  @override
  Future<PluginManifest?> load(String path) async => PluginManifest.parse(
    '{"version":1,"plugins":[{"id":"a.deps","label":"Dependencies"}]}',
  );

  @override
  Future<({PluginManifest? manifest, String? error})> tryLoad(
    String path,
  ) async => (manifest: await load(path), error: null);

  @override
  String get dartExecutable => 'dart';
}

Future<ShellController> _pumpShell(WidgetTester tester) async {
  var shell = ShellController(
    appContext: AppContext(logger: LogClient.print()),
    flutterSdk: FlutterSdkPath('/tmp/flutter'),
    registry: PluginRegistry({'a.deps': panelFor<_FakeCore>(_Fake.new)}),
    coreRegistry: PluginCoreRegistry({'a.deps': _FakeCore.new}),
    manifestLoader: _StubLoader(),
    discovery: WorktreeDiscovery(
      runProcess: (_, _, {workingDirectory}) async =>
          ProcessResult(0, 0, _listing, ''),
    ),
  );
  await shell.start('/repo');
  await tester.pumpWidget(ShellApp(shell));
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.byType(AddressBar));
  await tester.pumpAndSettle();
}

/// Taps the worktree segment, which is the switcher.
Future<void> _openSwitcher(WidgetTester tester, String worktree) async {
  await tester.tap(find.text(worktree));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String address) async {
  await tester.enterText(find.byType(TextField), address);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  group('the bar shows where the shell is', () {
    testWidgets('as parts, so the ends survive a narrow window', (
      tester,
    ) async {
      var shell = await _pumpShell(tester);
      expect(find.text('fw:///'), findsOneWidget);
      expect(find.text('~'), findsOneWidget);

      shell.go(
        Address(
          worktree: '~',
          plugin: 'a.deps',
          segments: ['app', 'tool/demos', 'avatar.dart#members'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('a.deps'), findsOneWidget);
      // The middle collapses under pressure; the last segment never does.
      expect(find.text('app/tool/demos'), findsOneWidget);
      expect(find.text('avatar.dart#members'), findsOneWidget);
    });

    testWidgets('applied axes read as chips, not as a query string', (
      tester,
    ) async {
      var shell = await _pumpShell(tester);

      shell.go(
        Address(
          worktree: '~',
          plugin: 'a.deps',
          axes: {'axis.theme': 'dark', 'knob.count': '3'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('theme dark'), findsOneWidget);
      expect(find.text('count 3'), findsOneWidget);
    });

    testWidgets('and follows it as it moves', (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Dependencies'));
      await tester.pumpAndSettle();

      expect(find.text('a.deps'), findsOneWidget);
    });

    testWidgets('expanding shows the whole address', (tester) async {
      var shell = await _pumpShell(tester);
      shell.selectChild('a.deps', 'packages/app');
      await tester.pumpAndSettle();

      await _expand(tester);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'fw:///~/a.deps/packages%2Fapp',
      );
    });
  });

  group('the bar drives the shell', () {
    testWidgets('a typed address opens what it names', (tester) async {
      await _pumpShell(tester);
      await _expand(tester);

      await _type(tester, 'fw:///~/a.deps/packages%2Fapp');

      expect(find.text('panel:a.deps/packages/app'), findsOneWidget);
      expect(find.text('packages/app'), findsOneWidget);
    });

    testWidgets('something that is not an address says so', (tester) async {
      await _pumpShell(tester);
      await _expand(tester);

      await _type(tester, 'not an address');

      expect(find.text('Not a flutterware address.'), findsOneWidget);
      // Still open, still holding what was typed: an error that closes the
      // thing you were editing is an error you cannot act on.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a worktree that exists but is closed is opened', (
      tester,
    ) async {
      var shell = await _pumpShell(tester);
      await _expand(tester);

      await _type(tester, 'fw:///repo-explorer/a.deps');

      // Typing an address is naming a destination, and opening the worktree is
      // how you get there. Explaining a refusal was the second-best answer.
      expect(shell.address.toString(), 'fw:///repo-explorer/a.deps');
      expect(shell.openWorktrees.map((w) => w.name), ['~', 'repo-explorer']);
      expect(find.textContaining('is not open'), findsNothing);
    });

    testWidgets('a worktree this repo has never heard of', (tester) async {
      await _pumpShell(tester);
      await _expand(tester);

      await _type(tester, 'fw:///nowhere/a.deps');

      expect(find.textContaining('No worktree named'), findsOneWidget);
    });
  });

  group('the worktree segment switches checkout', () {
    testWidgets('it offers the others by the name you would recognise', (
      tester,
    ) async {
      await _pumpShell(tester);

      await _openSwitcher(tester, '~');

      // Branches, because that is what a human knows a checkout by — with the
      // identity that actually goes in the address beside it. Scoped to the
      // menu: a branch name is also on a tab and in the rail above.
      expect(find.widgetWithText(MenuItemButton, 'main'), findsOneWidget);
      expect(
        find.widgetWithText(MenuItemButton, 'feature/explorer'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(MenuItemButton, 'repo-explorer'),
        findsOneWidget,
      );
      // Picking it will open it, and says so first.
      expect(find.widgetWithText(MenuItemButton, 'opens'), findsOneWidget);
    });

    testWidgets('picking one keeps the place and the axes', (tester) async {
      var shell = await _pumpShell(tester);
      shell.go(Address.parse('fw:///~/a.deps/packages%2Fapp?axis.theme=dark'));
      await tester.pumpAndSettle();

      await _openSwitcher(tester, '~');
      await tester.tap(find.widgetWithText(MenuItemButton, 'feature/explorer'));
      await tester.pumpAndSettle();

      // The whole point: same package, same theme, other checkout.
      expect(
        shell.address.toString(),
        'fw:///repo-explorer/a.deps/packages%2Fapp?axis.theme=dark',
      );
    });

    testWidgets('it opens instead of the editor', (tester) async {
      await _pumpShell(tester);

      await _openSwitcher(tester, '~');

      // The bar underneath is one big tap target for the editor; the segment
      // has to win the arena or the switcher can never be reached.
      expect(find.byType(TextField), findsNothing);
    });
  });
}
