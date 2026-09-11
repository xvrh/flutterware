import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/scenarios/axes.dart';
import 'package:flutterware_app/src/scenarios/film_encode.dart';
import 'package:flutterware_app/src/scenarios/runner.dart';
import 'package:path/path.dart' as p;

/// Renders `examples/brewline`'s shop scenario as a **film** and leaves the mp4
/// and a still per beat where they can be looked at — the "did anybody watch
/// it" check no assertion can make.
///
/// Not part of the suite (no `_test` suffix). Run it on purpose:
///
/// ```sh
/// cd app && fvm flutter test test/scenarios/manual_film_dump.dart
/// ```
///
/// Output: `build/film-dump/` — `film.mp4`, `film.json`, and `stills/*.png`,
/// one per beat, named after the beat so a picture can be traced back to the
/// moment that made it.
///
/// The Brewline order rather than the counter: it has a page transition, a
/// list, a selection, a typed name and a confirmation, which is enough of a
/// flow to judge pacing on. The whole film is the product here — watch it
/// before changing any of the beat defaults.
void main() {
  test('films the shop scenario into build/film-dump', () async {
    var repoRoot = Directory.current.parent.path;
    var outDir = p.join(repoRoot, 'build', 'film-dump');
    var frameDir = p.join(outDir, 'frames');
    var clip = p.join(outDir, 'film.mp4');
    var directory = Directory(outDir);
    if (directory.existsSync()) directory.deleteSync(recursive: true);

    var runner = ScenarioRunner(
      packageRoot: p.join(repoRoot, 'examples', 'brewline'),
      directory: 'test/scenarios',
      flutterSdkRoot: Platform.environment['FLUTTER_ROOT']!,
    );
    try {
      var watch = Stopwatch()..start();
      // The two halves run together, which is the whole design: the encoder
      // eats each frame as the harness writes it, so the 1.7GB this clip
      // would otherwise be never exists.
      var running = runner.run(
        outDir: p.join(outDir, 'run'),
        file: 'test/scenarios/mobile/shop_test.dart',
        scenario: 'Order a cappuccino',
        axes: const ScenarioAxes(device: 'iphone-13'),
        // A film is not evidence: nothing here needs a screenshot per step.
        pixels: ScenarioPixels.none,
        film: FilmSettings(directory: frameDir, scale: 2),
      );
      var film = await ScenarioFilmEncode(
        directory: frameDir,
        output: clip,
      ).drain(running);
      var report = await running;
      watch.stop();

      // A film of a scenario that broke is a clip that stops mid-flow, so say
      // so here rather than leaving it to be noticed in the pictures.
      for (var scenario in (report['scenarios'] as List?) ?? const []) {
        var record = (scenario as Map).cast<String, Object?>();
        if (record['ok'] == true) continue;
        print('FAILED: ${jsonEncode(record['errors'])}');
      }

      print(
        'filmed in ${watch.elapsedMilliseconds}ms: ${film.frames} frames of '
        '${film.width}x${film.height} at ${film.fps}fps '
        '(${(film.duration.inMilliseconds / 1000).toStringAsFixed(1)}s of '
        'film, ${(film.file.lengthSync() / 1024).round()} KB)',
      );
      for (var beat in film.beats) {
        print(
          '  ${beat['frame']}+${beat['frames']}  ${beat['kind']}'
          '${beat['verb'] == null ? '' : ' ${beat['verb']}'}'
          '${beat['target'] == null ? '' : ' ${beat['target']}'}',
        );
      }

      // One still per beat, out of the clip itself — every kind of moment can
      // then be looked at rather than only the ones a scrubber lands on.
      var stills = Directory(p.join(outDir, 'stills'))
        ..createSync(recursive: true);
      for (var beat in film.beats) {
        var length = beat['frames']! as int;
        var index = (beat['frame']! as int) + length ~/ 2;
        var name =
            '${'$index'.padLeft(4, '0')}-${beat['kind']}'
            '${beat['verb'] == null ? '' : '-${beat['verb']}'}.png';
        var still = await Process.run('ffmpeg', [
          '-hide_banner',
          '-loglevel',
          'error',
          '-i',
          clip,
          '-vf',
          "select='eq(n\\,$index)'",
          '-frames:v',
          '1',
          '-y',
          p.join(stills.path, name),
        ]);
        if (still.exitCode != 0) print('  (still $index: ${still.stderr})');
      }
      print('clip:   $clip');
      print('stills: ${stills.path}');
      // Left where the timeline can be read; the frames themselves are gone,
      // eaten by the encoder as they arrived.
      print('timeline: ${p.join(frameDir, ScenarioFilmNames.timeline)}');
    } finally {
      await runner.dispose();
    }
  });
}
