import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:path/path.dart' as p;

/// Records `examples/example`'s scenarios with motion and leaves the artifacts
/// where they can be looked at — the "did anybody watch it run" check that a
/// green assertion cannot make.
///
/// **Not part of the suite** (no `_test` suffix). Run it on purpose:
///
/// ```sh
/// cd app && fvm flutter test test/scenarios/manual_motion_dump.dart
/// ```
///
/// Output: `build/motion-dump/`, one directory of frames per recorded step.
void main() {
  test('records the example scenarios into build/motion-dump', () async {
    var repoRoot = Directory.current.parent.path;
    var outDir = p.join(repoRoot, 'build', 'motion-dump');
    var directory = Directory(outDir);
    if (directory.existsSync()) directory.deleteSync(recursive: true);

    var runner = ScenarioRunner(
      packageRoot: p.join(repoRoot, 'examples', 'example'),
      directory: 'test/scenarios',
      flutterSdkRoot: Platform.environment['FLUTTER_ROOT']!,
    );
    try {
      for (var scale in <double?>[null]) {
        var watch = Stopwatch()..start();
        var report = await runner.run(
          outDir: outDir,
          file: 'test/scenarios/counter_test.dart',
          scenario: 'Counter',
          captureScale: 1,
          // The panel's own settings: raw pixels, framed as a phone.
          captureRaw: true,
          axes: const ScenarioAxes(device: 'iphone-13'),
          recordInterval: const Duration(milliseconds: 33),
          recordScale: scale,
        );
        watch.stop();

        var scenario =
            (report['scenarios']! as List).single as Map<String, dynamic>;
        var steps = (scenario['steps']! as List).cast<Map<String, Object?>>();
        var frames = 0;
        var bytes = 0;
        for (var step in steps) {
          frames += (step['frameCount'] as int?) ?? 0;
          if (step['frames'] case String path) {
            for (var file in Directory(path).listSync().whereType<File>()) {
              bytes += file.lengthSync();
            }
          }
        }
        print(
          'record at $scale×: ${watch.elapsedMilliseconds}ms, '
          '$frames frames over ${steps.length} steps, '
          '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB on disk '
          '(${(bytes / frames / 1024).round()} KB/frame — and the same again '
          'in the image cache once decoded)',
        );
        for (var step in steps) {
          print(
            '  step ${step['index']} ${step['verb']} ${step['target'] ?? ''} '
            '— ${step['frameCount'] ?? 0} frames '
            '${step['frameWidth']}×${step['frameHeight']}',
          );
        }
      }
      print('artifacts: $outDir');
    } finally {
      await runner.dispose();
    }
  });
}
