// Do the two rendering lanes agree on pixels?
//
// The embedder guest composites through Impeller, the way the app does.
// `flutter_tester` runs the same widget tree under a fake clock. The
// comparison moved to the tester lane on a determinism argument, and its test
// pins that the tester lane is byte-identical *across its own renders* — not
// that the two lanes agree with each other. Nothing has ever asked that, and
// it decides whether a video may be rendered on the cheaper one.
//
//   cd app && fvm dart run tool/spike/lane_pixels.dart <entryId>
import 'dart:io';

import 'package:flutterware/plugins.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/plugins/native/previews_core.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  var wanted = args.isEmpty ? 'demos.fuse_label.fuseLabelPreview' : args.first;
  var repoRoot = p.dirname(Directory.current.absolute.path);
  var session = await Session.open(
    Directory(repoRoot),
    logger: LogClient.writeTo(stderr),
  );
  var previews = session.coreById('flutterware.previews')! as PreviewsCore;
  var scratch = Directory(p.join(Directory.systemTemp.path, 'fw-lane-pixels'))
    ..createSync(recursive: true);

  try {
    // Through the action, which is what warms the scan the runner reads.
    var listed = await session.invoke('previews', 'entries').done;
    if (!listed.ok) throw StateError('entries: ${listed.error}');
    var entries = previews.entriesFor('app');
    var entry = entries.firstWhere(
      (e) => e.id == wanted || e.id.endsWith(wanted),
      orElse: () => throw StateError(
        'no entry "$wanted". Known:\n  ${entries.map((e) => e.id).join('\n  ')}',
      ),
    );
    stdout.writeln('entry: ${entry.id}');

    // The embedder: real engine, real compositor, PNG out. Through the
    // action, because the catalog it renders from is the core's.
    var embedderWatch = Stopwatch()..start();
    var shot = await session
        .invoke('previews', 'screenshot', arguments: {'entry': entry.id})
        .done;
    embedderWatch.stop();
    if (!shot.ok) throw StateError('screenshot: ${shot.error}');
    var shotPath = (shot.value! as Artifact).path!;
    var embedder = img.decodePng(
      File(p.join(repoRoot, shotPath)).readAsBytesSync(),
    )!;
    stdout.writeln(
      'embedder: ${embedder.width}x${embedder.height} '
      'in ${embedderWatch.elapsedMilliseconds}ms',
    );

    // The tester: same widget tree, fake clock, raw rgba straight to disk.
    var testerWatch = Stopwatch()..start();
    img.Image? tester;
    await previews
        .testRunnerFor('app')
        .capture(
          entryIds: [entry.id],
          outDir: p.join(scratch.path, 'tester'),
          tree: false,
          onRow: (row) async {
            // Bare rgba, not the embedder's framed `.rawframe`: the harness
            // writes pixels and puts the dimensions on the row.
            if (row.image case String path?) {
              tester = img.Image.fromBytes(
                width: row.width,
                height: row.height,
                bytes: File(path).readAsBytesSync().buffer,
                numChannels: 4,
              );
            }
          },
        );
    testerWatch.stop();
    if (tester == null) {
      stdout.writeln('tester: handed back no frame');
      return;
    }
    stdout.writeln(
      'tester:   ${tester!.width}x${tester!.height} '
      'in ${testerWatch.elapsedMilliseconds}ms',
    );

    _report(embedder, tester!, scratch);
  } finally {
    session.dispose();
  }
}

/// How far apart the two pictures are, in the terms that decide the question:
/// identical, or near enough that a viewer could not tell, or not.
void _report(img.Image a, img.Image b, Directory scratch) {
  if (a.width != b.width || a.height != b.height) {
    stdout.writeln(
      'DIFFERENT SIZE — the lanes are not photographing the same '
      'thing, so pixels cannot be compared',
    );
    return;
  }

  var differing = 0;
  var worst = 0;
  var total = 0;
  var diff = img.Image(width: a.width, height: a.height);
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      var pa = a.getPixel(x, y);
      var pb = b.getPixel(x, y);
      var delta = [
        (pa.r - pb.r).abs(),
        (pa.g - pb.g).abs(),
        (pa.b - pb.b).abs(),
        (pa.a - pb.a).abs(),
      ].reduce((m, v) => v > m ? v : m).round();
      if (delta > 0) {
        differing++;
        total += delta;
        if (delta > worst) worst = delta;
      }
      // Amplified, because a difference worth arguing about can be one level
      // per channel and invisible at 1:1.
      var lit = (delta * 16).clamp(0, 255);
      diff.setPixelRgb(x, y, lit, lit, lit);
    }
  }

  var pixels = a.width * a.height;
  var percent = (differing / pixels * 100).toStringAsFixed(3);
  stdout.writeln(
    differing == 0
        ? 'IDENTICAL — every one of $pixels pixels matches'
        : 'DIFFERENT — $differing of $pixels pixels ($percent%), '
              'worst channel delta $worst, '
              'mean delta over differing pixels '
              '${(total / differing).toStringAsFixed(2)}',
  );
  if (differing > 0) {
    var out = File(p.join(scratch.path, 'diff.png'))
      ..writeAsBytesSync(img.encodePng(diff));
    stdout.writeln('diff (16x amplified): ${out.path}');
  }
}
