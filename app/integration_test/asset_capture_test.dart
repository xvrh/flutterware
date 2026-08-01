@Tags(['gpu'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutterware_app/src/previews/compiler_daemon_client.dart';
import 'package:flutterware_app/src/previews/headless_catalog.dart';
import 'package:flutterware_app/src/previews/package_config_locator.dart';
import 'package:flutterware_app/src/previews/protocol.dart';
import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A headless capture must contain the images the demo shows.
///
/// The regression this pins: image decode is asynchronous, so a capture taken
/// as soon as the layout exists photographs the demo *without* its pictures —
/// fonts perfect, images absent, nothing failing. `_settleImages` is the fix,
/// and this is the only check that can see it, because it needs a real guest
/// decoding a real file behind a real capture.
///
/// The subject is `examples/example`'s `asset_smoke` demo, whose fixture
/// images are flat Material blue (`#2196F3`) — a colour the demo's text,
/// chrome and background never use, so "the images arrived" is countable as
/// "the capture has thousands of pixels of it".
void main() {
  test('a capture of asset_smoke contains its images', () async {
    var appRoot = Directory.current.path;
    var repoRoot = p.dirname(appRoot);
    var exampleRoot = p.join(repoRoot, 'examples', 'example');
    var cache = FlutterCache.fromRunningSdk();
    var dartExecutable = p.join(cache.flutterRoot, 'bin', 'dart');
    var config = DaemonConfig(
      appPackageRoot: appRoot,
      projectRoot: exampleRoot,
      packageConfig: requirePackageConfig(exampleRoot),
      flutterSdkRoot: cache.flutterRoot,
      roots: const ['demo'],
    );

    // A daemon left over from an earlier run serves that run's kernel — which,
    // for a test about freshly-changed capture behaviour, is the one thing it
    // must not do.
    var (stale, _) = await CompilerDaemonClient.connect(
      dartExecutable: dartExecutable,
      config: config,
    );
    await stale.stopDaemon();

    var output = p.join(
      Directory.systemTemp.createTempSync('fw_asset_capture').path,
      'smoke.png',
    );
    var capture = await HeadlessCatalog(
      dartExecutable: dartExecutable,
      config: config,
    ).capture(entryId: 'demo/asset_smoke.dart#assetSmoke', output: output);

    var picture = img.decodePng(File(capture.file.path).readAsBytesSync())!;
    var fixtureBlue = 0;
    for (var pixel in picture) {
      if ((pixel.r - 0x21).abs() < 30 &&
          (pixel.g - 0x96).abs() < 30 &&
          (pixel.b - 0xf3).abs() < 30) {
        fixtureBlue++;
      }
    }

    // The two images cover ~48² + ~120² logical pixels of fill. Thousands when
    // they rendered, zero when the capture beat the decode.
    expect(
      fixtureBlue,
      greaterThan(5000),
      reason:
          'the capture at $output has $fixtureBlue pixels of the fixture '
          'blue — the images are missing from it',
    );
  });
}
