// SPIKE — not shipped. Measures what photographing a whole catalog costs, and
// how much of it a smaller render gives back.
//
//   fvm dart run tool/spike/capture_cost.dart <package> [ratio] [tree] [format]
//
// e.g. `tool/spike/capture_cost.dart app 0.25 false`. Prints the per-stage
// numbers the harness writes to stderr, plus totals.
import 'dart:async';
import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  var package = args.isEmpty ? 'app' : args[0];
  var pixelRatio = args.length > 1 ? double.parse(args[1]) : 1.0;
  var wantTree = args.length > 2 ? args[2] != 'false' : true;
  var format = args.length > 3 ? args[3] : 'raw';

  var worktree = Directory.current.path.endsWith('/app')
      ? p.dirname(Directory.current.path)
      : Directory.current.path;
  var packageRoot = p.join(worktree, package);
  // `resolvedExecutable` is `<flutter>/bin/cache/dart-sdk/bin/dart`, and what
  // the host wants is the Flutter root above all of that.
  var marker = '${p.separator}bin${p.separator}cache${p.separator}';
  var flutterSdkRoot = Platform.resolvedExecutable.contains(marker)
      ? Platform.resolvedExecutable.split(marker).first
      : p.dirname(p.dirname(Platform.resolvedExecutable));

  var roots = package == 'app' ? ['tool/catalog/demos'] : ['demo'];
  var scan = CatalogScanner(projectRoot: packageRoot, roots: roots).scan();
  var entries = scan.entries;
  stdout.writeln(
    'package=$package entries=${entries.length} ratio=$pixelRatio '
    'tree=$wantTree '
    'format=$format',
  );

  // `KEEP=<dir>` leaves the frames on disk, for looking at one.
  var keep = Platform.environment['KEEP'];
  var out = keep != null
      ? (Directory(keep)..createSync(recursive: true))
      : Directory.systemTemp.createTempSync('fw_capture_cost');
  var stages = <String, int>{};
  var perEntry = <(int, String)>[];
  var runner = PreviewTestRunner(
    packageRoot: packageRoot,
    flutterSdkRoot: flutterSdkRoot,
    // The canvases the package declares, mirroring `tool/flutterware.dart`.
    //
    // They change nothing here, and that is the point of passing them: a
    // desktop canvas is *offered, never staged* — `PreviewCanvas.defaultDevice`
    // returns null for a desktop device, because a window has no true size —
    // so `app`'s demos are framed on the plain 900x700 rectangle either way.
    // Worth stating, because the obvious reading of `devices: [window]` is that
    // entries render at 1280x800, and measuring on that assumption would put
    // every byte and every overflow in this file at the wrong size.
    read: () => (
      entries: entries,
      canvases: const [
        PreviewCanvas(
          '',
          devices: [Devices.window, Devices.smallWindow, Devices.wideWindow],
        ),
      ],
    ),
    onLog: (line) {
      if (line.contains('[entry] ')) {
        var parts = line.split('[entry] ').last.split(' ');
        var us = int.tryParse(parts.first);
        if (us != null) perEntry.add((us, parts.skip(1).join(' ')));
        return;
      }
      // The host prefixes the guest's console with `[tester] `.
      if (!line.contains('[capture] ')) return;
      for (var field in line.split(' ')) {
        var parts = field.split('=');
        if (parts.length != 2) continue;
        var value = int.tryParse(parts[1]);
        if (value == null) continue;
        stages[parts[0]] = (stages[parts[0]] ?? 0) + value;
      }
    },
  );

  var rows = 0;
  var broken = 0;
  var firstAt = Duration.zero;
  var whole = Stopwatch()..start();
  if (pixelRatio == 0) {
    // The control: render every entry and photograph none of it, so what a
    // picture costs is the difference between this and a capture run.
    var audited = await runner.audit(entryIds: [for (var e in entries) e.id]);
    firstAt = whole.elapsed;
    rows = audited.length;
    broken = audited.where((r) => (r.compileError ?? r.failure) != null).length;
  } else {
    await runner.capture(
      entryIds: [for (var e in entries) e.id],
      outDir: out.path,
      pixelRatio: pixelRatio,
      tree: wantTree,
      timings: true,
      format: format,
      onRow: (row) async {
        if (rows == 0) firstAt = whole.elapsed;
        // The directory a frame lands in is the entry's position in the list
        // handed over, which is not its position among the ones that *ran* —
        // a quarantined entry takes an index and writes nothing.
        if (keep != null) stdout.writeln('[index] $rows ${row.id}');
        rows++;
        if ((row.compileError ?? row.failure) != null) broken++;
      },
    );
  }
  var total = whole.elapsed;

  stdout
    ..writeln('rows=$rows broken=$broken')
    ..writeln('first row after ${firstAt.inMilliseconds}ms')
    ..writeln('total ${total.inMilliseconds}ms')
    ..writeln(
      'per entry ${(total.inMilliseconds / (rows == 0 ? 1 : rows)).toStringAsFixed(1)}ms',
    )
    ..writeln('stage totals (us, summed over entries): $stages')
    ..writeln(
      'per entry: ${{for (var e in stages.entries) e.key: e.key == 'kb' ? '${e.value ~/ (rows == 0 ? 1 : rows)}kb' : '${(e.value / (rows == 0 ? 1 : rows) / 1000).toStringAsFixed(2)}ms'}}',
    );

  if (perEntry.isNotEmpty) {
    var sorted = [...perEntry]..sort((a, b) => a.$1.compareTo(b.$1));
    String at(int percent) =>
        '${(sorted[(sorted.length - 1) * percent ~/ 100].$1 / 1000).toStringAsFixed(0)}ms';
    stdout
      ..writeln(
        'render p0=${at(0)} p50=${at(50)} p90=${at(90)} p99=${at(99)} '
        'max=${at(100)}',
      )
      ..writeln('slowest:');
    for (var (us, id) in sorted.reversed.take(8)) {
      stdout.writeln('  ${(us / 1000).toStringAsFixed(0)}ms  $id');
    }
    var head = sorted.reversed.take(10).fold(0, (a, e) => a + e.$1);
    var all = sorted.fold(0, (a, e) => a + e.$1);
    stdout.writeln(
      'top 10 entries are ${(head * 100 / all).toStringAsFixed(0)}% of all '
      'render time (${(all / 1000).toStringAsFixed(0)}ms)',
    );
  }

  await runner.dispose();
  if (keep == null) out.deleteSync(recursive: true);
  exit(0);
}
