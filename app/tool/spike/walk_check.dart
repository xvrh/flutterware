// Does the new walk render, and does it repeat itself?
//
//   cd app && fvm dart run tool/spike/walk_check.dart <entryId> [stops] [mode]
import 'dart:io';
import 'dart:typed_data';

// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/plugins/native/previews_core.dart';
import 'package:flutterware_app/src/previews/catalog_render.dart';
import 'package:flutterware_app/src/previews/devices.dart';
import 'package:flutterware_app/src/previews/tester_renderer.dart';
import 'package:flutterware_app/src/session/session.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  var wanted = args.isEmpty ? 'onboardingPagePreview' : args.first;
  var n = args.length > 1 ? int.parse(args[1]) : 9;
  var mode = args.length > 2 && args[2] == 'time'
      ? WalkMode.time
      : WalkMode.playhead;
  var stops = [for (var i = 0; i < n; i++) i / (n - 1)];

  var session = await Session.open(
    Directory(p.dirname(Directory.current.absolute.path)),
    logger: LogClient.writeTo(stderr),
  );
  try {
    var previews = session.coreById('flutterware.previews')! as PreviewsCore;
    var listed = await session.invoke('previews', 'entries').done;
    if (!listed.ok) throw StateError('entries: ${listed.error}');
    var entry = previews
        .entriesFor('app')
        .firstWhere((e) => e.id == wanted || e.id.endsWith(wanted));
    stdout.writeln('${entry.id}  ${stops.length} stops  ${mode.name}');

    var renderer = TesterRenderer(runner: previews.testRunnerFor('app'));
    Future<List<WalkFrame>> once() async {
      var watch = Stopwatch()..start();
      var frames = await renderer
          .walk(
            CatalogWalk(
              entryId: entry.id,
              stops: stops,
              mode: mode,
              viewport: CaptureViewport.panel,
            ),
          )
          .toList();
      stdout.writeln(
        '  ${frames.length} frames in ${watch.elapsedMilliseconds}ms '
        '(${frames.first.width}x${frames.first.height})',
      );
      return frames;
    }

    var a = await once();
    var b = await once();
    stdout.writeln('  ts: ${a.map((f) => f.t.toStringAsFixed(3)).join(' ')}');
    var differing = 0;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i].pixels, b[i].pixels)) differing++;
    }
    stdout.writeln(
      differing == 0
          ? '  REPEATS — both walks byte-identical across ${a.length} stops'
          : '  DIFFERS — $differing of ${a.length} stops',
    );
    // Same pictures walked backwards is what tells a scene from a state machine.
    var reversed = await renderer
        .walk(
          CatalogWalk(
            entryId: entry.id,
            stops: stops.reversed.toList(),
            mode: mode,
            viewport: CaptureViewport.panel,
          ),
        )
        .toList();
    var back = reversed.reversed.toList();
    var order = 0;
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i].pixels, back[i].pixels)) order++;
    }
    stdout.writeln(
      order == 0
          ? '  ORDER-FREE — backwards renders the same pictures'
          : '  ORDER-DEPENDENT — $order of ${a.length} stops differ backwards',
    );
  } finally {
    session.dispose();
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
