@Timeout(Duration(minutes: 4))
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

      // A new scenario file. No hot reload re-runs the generated entrypoint's
      // `main`, so this must take the restart lane — and prove the freshly
      // imported file arrives.
      var scratch = File(
        p.join(packageRoot, 'test', 'scenarios', 'scratch_test.dart'),
      );
      scratch.writeAsStringSync(_scratchSource('v1'));
      try {
        await runner.refresh();
        var refreshed = await runner.list();
        expect([
          for (var s in refreshed) '${s.file} ${s.name}',
        ], contains('test/scenarios/scratch_test.dart Scratch'));
        expect(
          _scratchTexts(
            await runner.run(
              outDir: outDir,
              file: 'test/scenarios/scratch_test.dart',
              scenario: 'Scratch',
            ),
          ),
          contains('v1'),
        );

        // A body edit. `run` on a warm runner refreshes by itself — the Run
        // button never replays stale code — and the same file set means this
        // takes the reload lane, not a restart.
        await Future<void>.delayed(const Duration(seconds: 1));
        scratch.writeAsStringSync(_scratchSource('v2'));
        expect(
          _scratchTexts(
            await runner.run(
              outDir: outDir,
              file: 'test/scenarios/scratch_test.dart',
              scenario: 'Scratch',
            ),
          ),
          contains('v2'),
        );
      } finally {
        scratch.deleteSync();
      }
    } finally {
      await runner.dispose();
      Directory(outDir).deleteSync(recursive: true);
    }
  });

  test('the entrypoint file is left alone when its content is right', () {
    var root = Directory.systemTemp.createTempSync('scenario_entrypoint');
    try {
      var path = writeHarnessEntrypoint(root.path, ['test/scenarios/a.dart']);
      var written = File(path).statSync().modified;
      writeHarnessEntrypoint(root.path, ['test/scenarios/a.dart']);
      expect(File(path).statSync().modified, written);
    } finally {
      root.deleteSync(recursive: true);
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

/// The last (only) step's texts of a single-scenario run report.
List<String> _scratchTexts(Map<String, Object?> report) {
  var scenarios = (report['scenarios']! as List).cast<Map<String, dynamic>>();
  var scratch = scenarios.single;
  expect(scratch['ok'], isTrue, reason: '${scratch['errors']}');
  var steps = (scratch['steps']! as List).cast<Map<String, dynamic>>();
  return (steps.last['texts']! as List).cast<String>();
}

String _scratchSource(String label) =>
    '''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Scratch', (s) async {
    await s.tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('$label'))),
    );
    await s.screen('shot');
  });
}
''';
