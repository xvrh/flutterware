import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:path/path.dart' as p;

/// What a *pixel-less* pass of a film costs, measured rather than assumed.
///
/// `pixels: false` is the dry pass: the beats still pump, the clock still
/// advances, the timeline is still written. So the difference between it and
/// the same run filmed is exactly what rasterising, composing and writing the
/// frames costs — which is the number a dry-run-then-render design has to be
/// priced against.
///
/// ```sh
/// cd app && fvm flutter test test/scenarios/manual_dry_run_cost.dart
/// ```
void main() {
  test('prices a dry pass against a filmed one', () async {
    var repoRoot = Directory.current.parent.path;
    var outDir = p.join(repoRoot, 'build', 'dry-cost');
    var directory = Directory(outDir);
    if (directory.existsSync()) directory.deleteSync(recursive: true);

    var runner = ScenarioRunner(
      packageRoot: p.join(repoRoot, 'examples', 'example'),
      directory: 'test/scenarios',
      flutterSdkRoot: Platform.environment['FLUTTER_ROOT']!,
    );

    Future<Map<String, Object?>> once(String label, FilmSettings film) async {
      var watch = Stopwatch()..start();
      await runner.run(
        outDir: p.join(outDir, label, 'run'),
        file: 'test/scenarios/mobile/shop_test.dart',
        scenario: 'Order a cappuccino',
        axes: const ScenarioAxes(device: 'iphone-13'),
        pixels: ScenarioPixels.none,
        film: film,
      );
      watch.stop();
      var timeline = jsonDecode(
        File(p.join(film.directory, 'film.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      var row = {
        'label': label,
        'wallMs': watch.elapsedMilliseconds,
        'frames': timeline['frames'],
        'dropped': timeline['dropped'],
        'composeMs': timeline['composeMs'],
        'writeMs': timeline['writeMs'],
      };
      print('MEASURE ${jsonEncode(row)}');
      return row;
    }

    FilmSettings settings(
      String label, {
      required double scale,
      bool dry = false,
    }) => FilmSettings(
      directory: p.join(outDir, label, 'frames'),
      scale: scale,
      pixels: !dry,
    );

    // Warm the host: the first run of a session pays the compile.
    await once('warmup', settings('warmup', scale: 2, dry: true));

    await once('dry-a', settings('dry-a', scale: 2, dry: true));
    await once('film-s2', settings('film-s2', scale: 2));
    await once('film-s3', settings('film-s3', scale: 3));
    await once('dry-b', settings('dry-b', scale: 2, dry: true));
    await once('film-s2-again', settings('film-s2-again', scale: 2));

    await runner.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
