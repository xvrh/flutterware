@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
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

      // Axes: the same warm harness, run as an iPhone in French, dark and
      // scaled — then bare again, proving the reset is per-run, not
      // per-process. The probe scenario prints what `MediaQuery` actually
      // sees, so these assertions are the app's view, not the harness's.
      var probe = File(
        p.join(packageRoot, 'test', 'scenarios', 'axes_probe_test.dart'),
      );
      probe.writeAsStringSync(_probeSource);
      try {
        var framed = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/axes_probe_test.dart',
          scenario: 'Probe',
          axes: const ScenarioAxes(
            device: 'iphone-se',
            language: 'fr-CA',
            textScale: 1.3,
            brightness: 'dark',
          ),
        );
        expect(
          _scratchTexts(framed),
          contains('375x667 2.0 20.0 fr-CA Brightness.dark 13.0'),
        );
        expect(_pngSize(_lastPng(framed)), (375, 667));

        var bare = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/axes_probe_test.dart',
          scenario: 'Probe',
        );
        var text = _scratchTexts(bare).single;
        expect(text, startsWith('800x600 3.0 0.0'));
        expect(text, contains('Brightness.light'));
        expect(text, endsWith('10.0'));
        expect(_pngSize(_lastPng(bare)), (800, 600));
      } finally {
        probe.deleteSync();
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

/// The last step's PNG path of a single-scenario run report.
String _lastPng(Map<String, Object?> report) {
  var steps = ((report['scenarios']! as List).single as Map)['steps']! as List;
  return (steps.last as Map)['png']! as String;
}

/// Width and height from the PNG's IHDR chunk — no decoder needed.
(int, int) _pngSize(String path) {
  var bytes = File(path).readAsBytesSync();
  int word(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  return (word(16), word(20));
}

/// Prints the app's own view of the axes: logical size, pixel ratio, the top
/// safe area, the platform locale, brightness, and 10 through the text
/// scaler.
const _probeSource = r'''
import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

void main() {
  scenario('Probe', (s) async {
    await s.tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              var media = MediaQuery.of(context);
              var locale = View.of(context).platformDispatcher.locale;
              return Text(
                '${media.size.width.round()}x${media.size.height.round()} '
                '${media.devicePixelRatio} '
                '${media.padding.top} '
                '${locale.toLanguageTag()} '
                '${media.platformBrightness} '
                '${media.textScaler.scale(10)}',
              );
            },
          ),
        ),
      ),
    );
    await s.screen('probe');
  });
}
''';
