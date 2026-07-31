import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_core.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// The `new` action — the authoring door.
///
/// Where it writes and what it refuses. That the scaffold it writes actually
/// runs is checked in `runner_test.dart`, where a real `flutter_tester` and a
/// real package already are.
void main() {
  late Directory root;

  ScenariosCore core({String? directory}) {
    var worktree = Worktree(path: root.path);
    return ScenariosCore(
      PluginHost(
        id: scenariosPluginId,
        label: 'Scenarios',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [Pkg('.')],
          discovered: ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: {
          'packages': [
            {'path': '.', 'directory': ?directory},
          ],
        },
      ),
    );
  }

  Future<ScenarioNewResult> write(
    ScenariosCore subject, {
    required String name,
    String? file,
  }) async =>
      (await subject.invoke('new', arguments: {'name': name, 'file': ?file}))!
          as ScenarioNewResult;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_scenarios_new_test');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('where it writes', () {
    test('names the file after the scenario, under the directory', () async {
      var result = await write(core(), name: 'Around the shop');

      expect(result.file, 'test/scenarios/around_the_shop_test.dart');
      expect(result.name, 'Around the shop');
      expect(File(p.join(root.path, result.file)).existsSync(), isTrue);
      // Package-relative, in the spelling `run --file=` takes — the next call
      // needs no translation.
      expect(result.next, contains('--file=${result.file}'));
      expect(result.next, contains('--scenario="Around the shop"'));
    });

    test('follows the configured directory', () async {
      var result = await write(core(directory: 'test/flows'), name: 'Checkout');

      expect(result.file, 'test/flows/checkout_test.dart');
      expect(File(p.join(root.path, result.file)).existsSync(), isTrue);
    });

    test('takes an explicit file', () async {
      var result = await write(
        core(),
        name: 'Checkout',
        file: 'test/scenarios/shop/pay_test.dart',
      );

      expect(result.file, 'test/scenarios/shop/pay_test.dart');
      expect(File(p.join(root.path, result.file)).existsSync(), isTrue);
    });
  });

  group('what it refuses', () {
    test('an existing file, rather than overwriting it', () async {
      var subject = core();
      await write(subject, name: 'Checkout');

      expect(
        () => write(subject, name: 'Checkout'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    // `flutter test` collects `*_test.dart` and nothing else, so this one is
    // the difference between a scenario CI runs and one it silently skips.
    test('a name `flutter test` would not collect', () async {
      expect(
        () => write(core(), name: 'Checkout', file: 'test/scenarios/pay.dart'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'message',
            contains('_test.dart'),
          ),
        ),
      );
    });

    test('a path that leaves the package', () async {
      expect(
        () => write(core(), name: 'Checkout', file: '../elsewhere_test.dart'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => write(core(), name: 'Checkout', file: '/tmp/elsewhere_test.dart'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty name', () async {
      expect(() => write(core(), name: '   '), throwsA(isA<ArgumentError>()));
    });
  });

  test('a name with an apostrophe still parses', () async {
    var result = await write(core(), name: "The barista's day");
    var source = File(p.join(root.path, result.file)).readAsStringSync();

    expect(result.file, 'test/scenarios/the_barista_s_day_test.dart');
    expect(source, contains(r"scenario('The barista\'s day'"));
  });
}
