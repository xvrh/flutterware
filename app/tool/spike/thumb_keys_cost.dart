// SPIKE — not shipped. What it costs to ask "do we already have this picture?"
//
//   fvm dart run app/tool/spike/thumb_keys_cost.dart [package]
//
// This is the cost the *sheet* pays before it draws anything: a content key per
// entry, then a lookup in the store. It runs on the UI isolate unless something
// moves it, so the number is what decides whether it may.
import 'dart:io';

import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:flutterware_app/src/previews/thumbnail_keys.dart';
import 'package:flutterware_app/src/utils/run_dir.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  var package = args.isEmpty ? 'app' : args[0];
  var worktree = Directory.current.path.endsWith('${p.separator}app')
      ? p.dirname(Directory.current.path)
      : Directory.current.path;
  var packageRoot = p.join(worktree, package);
  var roots = package == 'app' ? ['tool/catalog/demos'] : ['demo'];
  var entries = CatalogScanner(
    projectRoot: packageRoot,
    roots: roots,
  ).scan().entries;

  var keys = ThumbnailKeys(
    packageRoot: packageRoot,
    sdkKey: 'spike',
    extra: const {'longest': '700'},
  );

  var watch = Stopwatch()..start();
  var first = keys.keyFor(entries.first);
  var firstMs = watch.elapsedMilliseconds;

  watch.reset();
  var computed = [for (var entry in entries) keys.keyFor(entry)];
  var allMs = watch.elapsedMilliseconds;

  watch.reset();
  for (var entry in entries) {
    keys.keyFor(entry);
  }
  var memoUs = watch.elapsedMicroseconds;

  // And the same again off the isolate, which is what the page actually does.
  var offMain = ThumbnailKeys(
    packageRoot: packageRoot,
    sdkKey: 'spike',
    extra: const {'longest': '700'},
  );
  watch.reset();
  await offMain.warm(entries);
  var warmMs = watch.elapsedMilliseconds;
  var sameAsSync = entries.every((e) => offMain.keyFor(e) == keys.keyFor(e));

  var shots = ShotCache(p.join(flutterwareDir(), 'shots'));
  watch.reset();
  var present = computed.where(shots.has).length;
  var lookupUs = watch.elapsedMicroseconds;

  stdout
    ..writeln('package=$package entries=${entries.length}')
    ..writeln('first key (graph + pixel inputs + one closure): ${firstMs}ms')
    ..writeln('every key, cold: ${allMs}ms')
    ..writeln('all of them again, memoised: ${memoUs}us')
    ..writeln(
      'already in the store: $present of ${entries.length} '
      '(${lookupUs}us to ask)',
    )
    ..writeln('distinct keys: ${computed.toSet().length}')
    ..writeln('warm() off the isolate: ${warmMs}ms, same keys: $sameAsSync');
  if (first != computed.first) stdout.writeln('!! key not stable');
}
