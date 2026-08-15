import 'dart:io';

import 'package:flutterware_app/src/previews/devices.dart';
import 'package:flutterware_app/src/previews/headless_catalog.dart';
import 'package:flutterware_app/src/previews/package_config_locator.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:path/path.dart' as p;

/// A filmstrip of a Motion demo, straight out of the headless pipeline.
///
/// The demos drive their playhead from a `t` knob, so "render this motion at
/// 40%" is just a capture with a knob turned — no panel, no transport, no GUI.
/// That is the shape the plugin's `filmstrip` action will have; this is it with
/// the argument parsing left out.
///
/// ```sh
/// cd app && dart run tool/catalog/motion_shots.dart [entry-substring]
/// ```
Future<void> main(List<String> args) async {
  // `motion_`, not `motion`: the S5 spike stage is also called that and drives
  // its playhead from a VM extension rather than a knob, so it has no `t` to
  // turn and a capture of it would fail on the way in.
  var wanted = args.isEmpty ? 'motion_' : args.first;
  var frames = const [0.0, 0.25, 0.45, 0.7, 1.0];

  var appPackageRoot = p.dirname(
    p.dirname(p.dirname(p.fromUri(Platform.script))),
  );
  var cache = FlutterCache.fromRunningSdk();
  var outputDir = Platform.environment['MOTION_SHOTS_DIR'] ?? 'build/shots';

  var catalog = HeadlessCatalog(
    dartExecutable: p.join(cache.flutterRoot, 'bin', 'dart'),
    config: DaemonConfig(
      appPackageRoot: appPackageRoot,
      projectRoot: appPackageRoot,
      packageConfig: requirePackageConfig(appPackageRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: ['tool/catalog/demos'],
    ),
  );

  var checked = await catalog.check();
  var entries = [
    for (var entry in checked.servable)
      if (entry.id.contains(wanted)) entry.id,
  ]..sort();
  if (entries.isEmpty) {
    stderr.writeln('[shots] nothing matched "$wanted"');
    exit(1);
  }

  // A phone-shaped canvas at 2x — what the demos were composed against.
  var viewport = const CaptureViewport(width: 800, height: 1440, pixelRatio: 2);

  for (var entryId in entries) {
    var slug = entryId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    for (var t in frames) {
      var name = '$slug-t${(t * 100).round().toString().padLeft(3, '0')}.png';
      var output = p.join(outputDir, name);
      var capture = await catalog.capture(
        entryId: entryId,
        output: output,
        viewport: viewport,
        knobs: {'t': '$t'},
      );
      stdout.writeln('[shots] ${capture.file}');
    }
  }
  exit(0);
}
