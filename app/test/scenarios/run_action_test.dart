import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_core.dart';
import 'package:flutterware_app/src/plugins/native/scenarios_results.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// The `run` action's answers, over a fake runner.
///
/// Mostly about the case that used to be silent: a `file` or `scenario` that
/// matched nothing came back as an empty list and a zero exit, so a typo read
/// as a green run. The runner is faked because none of this is about running.
void main() {
  late Directory root;

  ScenariosCore core(_FakeRunner runner) {
    var worktree = Worktree(path: root.path);
    var subject = ScenariosCore(
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
            {'path': '.'},
          ],
        },
      ),
    );
    subject.debugInstallRunner('.', runner);
    return subject;
  }

  void writeScenarios(String file, List<String> names) {
    var target = File(p.join(root.path, 'test', 'scenarios', file));
    target.parent.createSync(recursive: true);
    target.writeAsStringSync('''
import 'package:flutterware/flutter_test.dart';

void main() {
${names.map((n) => "  scenario('$n', (s) async {});").join('\n')}
}
''');
  }

  Future<ScenarioRunResult> run(
    ScenariosCore subject, {
    String? file,
    String? scenario,
  }) async =>
      (await subject.invoke(
            'run',
            arguments: {'file': ?file, 'scenario': ?scenario},
          ))!
          as ScenarioRunResult;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fw_scenarios_run_test');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('a selector that matched nothing', () {
    test('names the scenarios the file does declare', () async {
      writeScenarios('shop_test.dart', ['Around the shop', 'Order a coffee']);

      var result = await run(
        core(_FakeRunner(matches: false)),
        file: 'test/scenarios/shop_test.dart',
        scenario: 'Arund the shop',
      );

      expect(result.ok, isFalse);
      var error = result.packages.single.error!;
      expect(error, contains('No scenario "Arund the shop"'));
      expect(error, contains('"Around the shop"'));
      expect(error, contains('"Order a coffee"'));
    });

    test('names the files, when the file itself is the typo', () async {
      writeScenarios('shop_test.dart', ['Around the shop']);

      var result = await run(
        core(_FakeRunner(matches: false)),
        file: 'test/scenarios/shopp_test.dart',
      );

      expect(result.ok, isFalse);
      expect(
        result.packages.single.error,
        allOf(
          contains('No scenarios in "test/scenarios/shopp_test.dart"'),
          contains('test/scenarios/shop_test.dart'),
        ),
      );
    });

    test('hands back the authoring hint when there are none at all', () async {
      var result = await run(
        core(_FakeRunner(matches: false)),
        file: 'test/scenarios/shop_test.dart',
      );

      expect(result.ok, isFalse);
      expect(
        result.packages.single.error,
        allOf(
          contains('no scenarios at all'),
          contains('package:flutterware/flutter_test.dart'),
          contains('fw run scenarios new'),
        ),
      );
    });
  });

  test('an unselected run that finds nothing is not an error', () async {
    // No `file`, no `scenario`: "run everything" over an empty suite ran
    // everything there was. Nothing was asked for by name, so nothing is
    // missing.
    var result = await run(core(_FakeRunner(matches: false)));

    expect(result.packages.single.error, isNull);
    expect(result.ok, isTrue);
  });

  group('ok', () {
    test('is false when a scenario came back red', () async {
      var result = await run(core(_FakeRunner(ok: false)));

      expect(result.ok, isFalse);
    });

    test('is false when the package could not run at all', () async {
      var result = await run(core(_FakeRunner(failure: 'does not compile')));

      expect(result.ok, isFalse);
      expect(result.packages.single.error, contains('does not compile'));
    });

    test('is true for a green run', () async {
      var result = await run(core(_FakeRunner()));

      expect(result.ok, isTrue);
    });
  });
}

/// Returns whatever the test needs it to: nothing, a green scenario, a red
/// one, or a failure to run at all.
class _FakeRunner extends ScenarioRunner {
  _FakeRunner({this.ok = true, this.failure, this.matches = true})
    : super(packageRoot: '/none', directory: 'none', flutterSdkRoot: '/none');

  final bool ok;
  final String? failure;

  /// False stands for the harness running the suite and finding nothing the
  /// selector named — what a misspelling actually produces.
  final bool matches;

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
    DateTime? clock,
  }) async {
    if (failure case var failure?) throw StateError(failure);
    if (!matches) return {'ms': 1, 'scenarios': <Object?>[]};
    return {
      'ms': 5,
      'scenarios': [
        {
          'file': file ?? 'test/scenarios/a_test.dart',
          'name': scenario ?? 'A',
          'ok': ok,
          'ms': 3,
          'steps': <Object?>[],
          'errors': [
            if (!ok) {'error': 'expected 2, found 1'},
          ],
        },
      ],
    };
  }

  @override
  Future<void> dispose() async {}
}
