@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/harness_entrypoint.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:path/path.dart' as p;

/// End-to-end: the real `examples/example` package, a real `flutter_tester`,
/// a real run. Slow (a cold harness compile), so everything is exercised in
/// one warm sequence rather than one test per assertion.
void main() {
  test('lists, runs, and writes the step triple', () async {
    var flutterRoot = Platform.environment['FLUTTER_ROOT'];
    expect(
      flutterRoot,
      isNotNull,
      reason: 'flutter test always sets FLUTTER_ROOT',
    );
    // app/ → the repo root, the workspace this test runs in.
    var repoRoot = Directory.current.parent.path;
    var packageRoot = p.join(repoRoot, 'examples', 'example');
    var outDir = Directory.systemTemp.createTempSync('scenario_run').path;

    var runner = ScenarioRunner(
      packageRoot: packageRoot,
      directory: 'test/scenarios',
      flutterSdkRoot: flutterRoot!,
    );
    try {
      var listed = await runner.list();
      expect([
        for (var s in listed) '${s.file} ${s.name}',
      ], contains('test/scenarios/counter_test.dart Counter'));

      var report = await runner.run(
        outDir: outDir,
        file: 'test/scenarios/counter_test.dart',
        scenario: 'Counter',
      );
      var scenarios = (report['scenarios']! as List)
          .cast<Map<String, dynamic>>();
      expect(scenarios, hasLength(1));
      var counter = scenarios.single;
      expect(counter['ok'], isTrue, reason: '${counter['errors']}');

      var steps = (counter['steps']! as List).cast<Map<String, dynamic>>();
      // Two auto taps, one named shot, one auto enterText, one screen().
      expect(steps, hasLength(5));
      expect([
        for (var s in steps) s['name'],
      ], containsAll(['Counted to two', 'Labelled']));
      for (var step in steps) {
        var png = File(step['png']! as String);
        expect(png.existsSync(), isTrue);
        expect(png.lengthSync(), greaterThan(1000));
        var tree =
            jsonDecode(File(step['tree']! as String).readAsStringSync())
                as Map<String, dynamic>;
        expect(tree['root'], isNotNull);
      }
      var last = steps.last;
      expect((last['texts']! as List).cast<String>(), contains('a label'));

      // Warm re-run: the compiled harness and the live tester are reused, so
      // this is the instantaneous FakeAsync loop, not a second cold start.
      var watch = Stopwatch()..start();
      var rerun = await runner.run(
        outDir: outDir,
        file: 'test/scenarios/counter_test.dart',
        scenario: 'Counter',
      );
      expect(((rerun['scenarios']! as List).single as Map)['ok'], isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    } finally {
      await runner.dispose();
      Directory(outDir).deleteSync(recursive: true);
    }
  });

  test('the generated entrypoint is stable and relative', () {
    var source = generateHarnessEntrypoint([
      'test/scenarios/b_test.dart',
      'test/scenarios/a_test.dart',
    ]);
    expect(
      source,
      '// GENERATED — flutterware scenarios harness. Do not edit.\n'
      "import 'package:flutterware/src/scenarios/harness.dart'\n"
      '    as harness;\n'
      "import '../../test/scenarios/a_test.dart' as s0;\n"
      "import '../../test/scenarios/b_test.dart' as s1;\n"
      '\n'
      'void main() => harness.runHarness({\n'
      "  'test/scenarios/a_test.dart': s0.main,\n"
      "  'test/scenarios/b_test.dart': s1.main,\n"
      '});\n',
    );
  });
}
