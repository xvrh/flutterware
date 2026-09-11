import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:path/path.dart' as p;

/// What a *pool* of concurrent scenario instances costs.
///
/// A reel that dissolves two sources, or lays six out in a grid, needs that
/// many scenarios alive at once — and a test binding is a singleton, so each
/// one is a guest process of its own with a build lane of its own. This
/// prices that: how long N guests take to come up cold and warm, and what
/// each one weighs while it is up.
///
/// ```sh
/// cd app && fvm flutter test test/scenarios/manual_instance_pool_cost.dart
/// ```
void main() {
  test('prices a pool of 1, 2 and 6 concurrent instances', () async {
    var repoRoot = Directory.current.parent.path;
    var example = p.join(repoRoot, 'examples', 'brewline');
    var probeRoot = p.join(repoRoot, 'build', 'pool-probe');

    Future<int> testerMemoryMb() async {
      var ps = await Process.run('ps', ['-axo', 'rss=,command=']);
      var total = 0;
      var count = 0;
      for (var line in (ps.stdout as String).split('\n')) {
        if (!line.contains('flutter_tester')) continue;
        var rss = int.tryParse(line.trimLeft().split(RegExp(r'\s+')).first);
        if (rss == null) continue;
        total += rss;
        count++;
      }
      return count == 0 ? 0 : (total ~/ count) ~/ 1024;
    }

    Future<void> round(int n, {required String phase}) async {
      var runners = [
        for (var i = 0; i < n; i++)
          ScenarioRunner(
            packageRoot: example,
            directory: 'test/scenarios',
            flutterSdkRoot: Platform.environment['FLUTTER_ROOT']!,
            buildDirectory: p.join('build', 'pool-probe', 'lane-$i'),
          ),
      ];
      var watch = Stopwatch()..start();
      await Future.wait([
        for (var i = 0; i < n; i++)
          runners[i].run(
            outDir: p.join(probeRoot, 'out', '$phase-$n-$i'),
            file: 'test/scenarios/mobile/shop_test.dart',
            scenario: 'Order a cappuccino',
            axes: const ScenarioAxes(device: 'iphone-13'),
            pixels: ScenarioPixels.none,
            // A dry pass: every beat pumps, nothing rasterises.
            film: FilmSettings(
              directory: p.join(probeRoot, 'frames', '$phase-$n-$i'),
              pixels: false,
            ),
          ),
      ]);
      watch.stop();
      // Guests stay warm after a run, so this is the pool at rest.
      var mb = await testerMemoryMb();
      print(
        'MEASURE ${jsonEncode({'phase': phase, 'instances': n, 'wallMs': watch.elapsedMilliseconds, 'avgTesterMb': mb})}',
      );
      await Future.wait([for (var r in runners) r.dispose()]);
    }

    var dir = Directory(probeRoot);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    for (var i = 0; i < 6; i++) {
      var lane = Directory(p.join(example, 'build', 'pool-probe', 'lane-$i'));
      if (lane.existsSync()) lane.deleteSync(recursive: true);
    }

    for (var n in [1, 2, 6]) {
      await round(n, phase: 'cold');
    }
    for (var n in [1, 2, 6]) {
      await round(n, phase: 'warm');
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
