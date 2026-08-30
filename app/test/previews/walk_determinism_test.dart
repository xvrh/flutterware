@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/embedder/build_directory.dart';
import 'package:flutterware_app/src/previews/catalog_render.dart';
import 'package:flutterware_app/src/previews/discovery.dart';
import 'package:flutterware_app/src/previews/test_runner.dart';
import 'package:flutterware_app/src/previews/tester_renderer.dart';

/// **The property the export lane exists for.**
///
/// A clip is a list of moments, and nothing downstream can tell a frame of the
/// wrong moment from a frame of the right one — every picture looks perfectly
/// plausible. So the guarantee has to be pinned here or it is not a guarantee.
///
/// Two claims, and the second is the stronger one:
///
///   * **A walk repeats.** The same stops rendered twice are byte-identical.
///   * **A walk is order-free.** The same stops rendered *backwards* are the
///     same pictures. That is what says the screen is a function of its
///     playhead rather than of its history, and it is the mechanical form of
///     the rule every frame-based renderer states as doctrine.
///
/// Measured 2026-08-30, this is exactly what the embedder guest could not do:
/// over six trials of `onboardingPageMotion` it rendered a *different* clip
/// from an identical walk in four of them, frames offset by a stop, because it
/// advances the playhead on the UI thread and writes whatever its rasteriser
/// presents. The harness has no second thread to lose — `toImage` rasterises
/// the layer tree the pump just produced.
///
/// The fixtures are this app's own demos rather than `examples/example`, which
/// mounts no `MotionScope`. Two of them, chosen because they fail differently:
/// a scene, and a flow that moves a `PageView` from a post-frame callback and
/// therefore only lands its playhead on a second, timeless frame.
void main() {
  var fixtures = {
    'a scene': 'tool/catalog/demos/onboarding_page.dart#onboardingPagePreview',
    'a flow that applies its playhead late':
        'tool/catalog/demos/onboarding.dart#onboarding',
  };

  for (var MapEntry(key: what, value: entryId) in fixtures.entries) {
    test('a walk of $what repeats itself and is order-free', () async {
      var flutterRoot = Platform.environment['FLUTTER_ROOT'];
      expect(flutterRoot, isNotNull, reason: 'flutter test always sets it');
      var packageRoot = Directory.current.path;

      var scan = CatalogScanner(
        projectRoot: packageRoot,
        roots: const ['tool/catalog/demos'],
      ).scan();
      var entry = scan.entries.singleWhere((entry) => entry.id == entryId);

      var runner = PreviewTestRunner(
        packageRoot: packageRoot,
        flutterSdkRoot: flutterRoot!,
        read: () => (entries: [entry], canvases: const []),
        buildDirectory: claimBuildDirectory(
          packageRoot,
          root: comparisonBuildRoot,
        ),
      );
      try {
        var renderer = TesterRenderer(runner: runner);
        var stops = [for (var i = 0; i < 5; i++) i / 4];
        Future<List<WalkFrame>> walk(List<double> order) => renderer
            .walk(CatalogWalk(entryId: entry.id, stops: order))
            .toList();

        var first = await walk(stops);
        expect(first, hasLength(stops.length));
        expect(
          [for (var frame in first) frame.t],
          stops,
          reason: 'a frame carries the stop it is of, never its position',
        );

        var again = await walk(stops);
        for (var i = 0; i < stops.length; i++) {
          expect(
            again[i].pixels,
            first[i].pixels,
            reason: 'stop ${stops[i]} differed between two identical walks',
          );
        }

        var backwards = (await walk(stops.reversed.toList())).reversed.toList();
        for (var i = 0; i < stops.length; i++) {
          expect(
            backwards[i].pixels,
            first[i].pixels,
            reason:
                'stop ${stops[i]} differed when the walk was taken backwards, '
                'so this screen renders its history rather than its playhead',
          );
        }
      } finally {
        await runner.dispose();
      }
    });
  }
}
