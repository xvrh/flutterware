import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/demo/page_title.dart';
import 'package:flutterware_app/src/demo/page_url.dart';
import 'package:flutterware_app/src/demo/recorded_project.dart';
import 'package:flutterware_app/src/demo/recording.dart';
import 'package:flutterware_app/src/plugins/native/icon_plugin.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_address.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_plugin.dart';
import 'package:flutterware_app/src/shell/shell_controller.dart';
import 'package:flutterware_app/src/shell/shell_view.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:path/path.dart' as p;

void main() {
  group('a fragment names an address', () {
    // Each one as the browser hands it back: written through `Uri`, the way
    // the page writes it, and read out of the href it ends up in.
    String throughTheBrowser(Address address) => Uri.parse(
      'https://example.test/flutterware/${Uri(fragment: PageUrl.fragmentOf(address))}',
    ).fragment;

    for (var address in [
      Address(worktree: Worktree.mainName),
      Address(space: Address.worktreesSpace),
      // The root package is `.`, which a path would resolve away.
      Address(
        worktree: Worktree.mainName,
        plugin: 'flutterware.previews',
        segments: ['.', 'demo', 'shop.dart#shopConfirmation'],
        axes: {'axis.theme': 'dark'},
      ),
      Address(
        worktree: Worktree.mainName,
        plugin: scenariosPluginId,
        segments: scenarioSegments(
          '.',
          file: 'test/scenarios/mobile/shop_test.dart',
          scenario: 'Around the shop',
          step: 2,
        ),
      ),
      Address(
        worktree: 'feature/crème',
        plugin: 'a.b',
        segments: ['50% & more?'],
        axes: {'knob.label': 'a b/c'},
      ),
    ]) {
      test('$address', () {
        expect(PageUrl.addressOf(throughTheBrowser(address)), address);
      });
    }

    test('an empty fragment or a stranger names nothing', () {
      expect(PageUrl.addressOf(''), isNull);
      expect(PageUrl.addressOf('section-2'), isNull);
    });
  });

  group('the page URL follows the shell', () {
    final recording = FileScenarioArtifacts(
      p.join(Directory.current.path, 'demo', 'fixture'),
    );

    late List<String> pushed;
    late List<String> replaced;
    late List<String> written;
    late StreamController<String> browser;

    Future<(ShellController, PageUrl)> open(
      WidgetTester tester, {
      Address? landing,
    }) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      pushed = [];
      replaced = [];
      written = [];
      browser = StreamController<String>();
      addTearDown(browser.close);

      var shell = recordedShell(recording: recording);
      addTearDown(shell.dispose);
      var page = PageUrl(
        shell,
        push: (fragment) {
          pushed.add(fragment);
          written.add(fragment);
        },
        replace: (fragment) {
          replaced.add(fragment);
          written.add(fragment);
        },
        changes: browser.stream,
      )..attach();
      addTearDown(page.dispose);
      await shell.start(recordedProjectRoot, landing: landing);
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();
      return (shell, page);
    }

    final scenario = Address(
      worktree: Worktree.mainName,
      plugin: scenariosPluginId,
      segments: scenarioSegments(
        '.',
        file: 'test/scenarios/mobile/shop_test.dart',
        scenario: 'Order a cappuccino',
      ),
    );

    testWidgets('a link lands where it names, and costs no history entry', (
      tester,
    ) async {
      var (shell, _) = await open(tester, landing: scenario);

      expect(shell.address.bare, scenario);
      expect(shell.selectedSession, isNotNull);
      expect(pushed, isEmpty);
      expect(PageUrl.addressOf(replaced.last)?.bare, scenario);
    });

    testWidgets('a link naming no worktree opens the project as usual', (
      tester,
    ) async {
      var (shell, _) = await open(
        tester,
        landing: Address(worktree: 'nowhere', plugin: scenariosPluginId),
      );

      expect(shell.address, Address(worktree: Worktree.mainName));
      expect(pushed, isEmpty);
    });

    testWidgets('a tap that moves pushes; a move nothing pressed for replaces', (
      tester,
    ) async {
      var (shell, _) = await open(tester);

      await tester.tap(find.text('Launcher icon'));
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(PageUrl.addressOf(pushed.single)?.plugin, launcherIconPluginId);
      // Whatever the panel wrote after landing replaced the entry the tap made.
      expect(PageUrl.addressOf(written.last), shell.address);

      // Moved by something other than a hand: a replacement.
      shell.go(scenario);
      await tester.pumpAndSettle();
      expect(pushed, hasLength(1));
      expect(PageUrl.addressOf(replaced.last)?.bare, scenario);
    });

    testWidgets('an axis alone replaces, even under a hand', (tester) async {
      var (shell, _) = await open(tester, landing: scenario);
      replaced.clear();

      // A key that does nothing, then the axis it would have set.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      shell.go(shell.address.withAxes({'axis.theme': 'dark'}));
      await tester.pumpAndSettle();

      expect(pushed, isEmpty);
      expect(PageUrl.addressOf(replaced.single)?.axes, {'axis.theme': 'dark'});
    });

    testWidgets('a press moves the page even when the address follows later', (
      tester,
    ) async {
      var (shell, _) = await open(tester);

      // A demo clicked in the catalog: the address is written once the demo
      // has drawn, long after the click let go.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(seconds: 1));
      shell.go(scenario);
      await tester.pumpAndSettle();
      expect(pushed, hasLength(1));

      // Spent: what the panel restates after it is a replacement.
      shell.go(scenario.child('1'));
      await tester.pumpAndSettle();
      expect(pushed, hasLength(1));
    });

    testWidgets('a write during the press does not cost the tap its entry', (
      tester,
    ) async {
      var (shell, _) = await open(tester);

      // What the page does between a mouse down and its up: a panel settling
      // restates an axis. The tap that follows still moves somewhere.
      var gesture = await tester.startGesture(
        tester.getCenter(find.text('Launcher icon')),
      );
      shell.go(shell.address.withAxes({'axis.theme': 'dark'}));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(PageUrl.addressOf(pushed.single)?.plugin, launcherIconPluginId);
    });

    testWidgets('back in the browser moves the shell without a new entry', (
      tester,
    ) async {
      var (shell, _) = await open(tester, landing: scenario);

      await tester.tap(find.text('Launcher icon'));
      await tester.pumpAndSettle();
      expect(pushed, hasLength(1));

      browser.add(PageUrl.fragmentOf(scenario));
      await tester.pumpAndSettle();

      expect(shell.address.bare, scenario);
      expect(pushed, hasLength(1));
    });
  });

  group('the page title', () {
    final recording = FileScenarioArtifacts(
      p.join(Directory.current.path, 'demo', 'fixture'),
    );

    testWidgets('names the place, in the words the window uses', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var shell = recordedShell(recording: recording);
      addTearDown(shell.dispose);
      var titles = <String>[];
      addTearDown(followPageTitle(shell, titles.add));
      await shell.start(recordedProjectRoot);
      await tester.pumpWidget(ShellApp(shell));
      await tester.pumpAndSettle();
      expect(titles.last, 'flutterware');

      await tester.tap(find.text('Scenarios'));
      await tester.pumpAndSettle();
      expect(titles.last, 'Scenarios · flutterware');

      await tester.tap(find.text('Order a cappuccino'));
      await tester.pumpAndSettle();
      expect(titles.last, 'Order a cappuccino · Scenarios · flutterware');

      // A step reads as its scenario: no row names the step itself.
      shell.go(
        shell.address.copyWith(segments: [...shell.address.segments, '1']),
      );
      await tester.pumpAndSettle();
      expect(titles.last, 'Order a cappuccino · Scenarios · flutterware');

      shell.selectChanges();
      await tester.pumpAndSettle();
      expect(titles.last, 'Changes · flutterware');
    });
  });
}
