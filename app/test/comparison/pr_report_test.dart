import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/artifact.dart';
import 'package:flutterware_app/src/comparison/channels.dart';
import 'package:flutterware_app/src/comparison/frame_ref.dart';
import 'package:flutterware_app/src/comparison/pixel_diff.dart';
import 'package:flutterware_app/src/comparison/pr_report.dart';
import 'package:flutterware_app/src/comparison/runner.dart';
import 'package:flutterware_app/src/comparison/scenario_comparison.dart';
import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late ShotCache cache;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fw_pr_report');
    cache = ShotCache(p.join(temp.path, 'shots'));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  void file(String key, int value, {int width = 6, int height = 6}) {
    cache.write(
      key,
      Uint8List(width * height * 4)..fillRange(0, width * height * 4, value),
      ShotRecord(
        format: 'raw',
        width: width,
        height: height,
        entryId: 'demo/card.dart#card',
      ),
    );
  }

  ComparisonResult previews(List<ComparedItem> items) => ComparisonResult(
    baseSha: 'abc',
    headRoot: '/w',
    elapsed: const Duration(milliseconds: 100),
    rendered: items.length,
    items: items,
  );

  test('a clean comparison is a short comment and no mosaic', () {
    var report = writePrReport(
      artifact: ComparisonArtifact(
        previews: previews(const [
          ComparedItem(id: 'demo/a.dart#a', state: ComparedState.same),
          ComparedItem(id: 'demo/b.dart#b', state: ComparedState.skipped),
        ]),
      ),
      cache: cache,
      against: 'master',
      directory: p.join(temp.path, 'report'),
    );

    expect(report.mosaicPath, isNull);
    var comment = File(report.commentPath).readAsStringSync();
    expect(comment, contains('Nothing changed'));
    expect(comment, contains('2 entries compared'));
    expect(comment, isNot(contains(mosaicUrlPlaceholder)));
  });

  test('findings become a table, a mosaic and placeholder links', () {
    file('k-base', 40);
    file('k-head', 200);
    var report = writePrReport(
      artifact: ComparisonArtifact(
        previews: previews([
          ComparedItem(
            id: 'demo/card.dart#card',
            state: ComparedState.changed,
            pixels: PixelChannel(
              PixelDiff(
                width: 6,
                height: 6,
                changedPixels: 36,
                comparedPixels: 36,
                sizeChanged: false,
                clusters: const [
                  DiffRect(x: 0, y: 0, width: 6, height: 6, pixels: 36),
                ],
              ),
            ),
            shots: (base: 'k-base', head: 'k-head'),
          ),
        ]),
      ),
      cache: cache,
      against: 'master',
      directory: p.join(temp.path, 'report'),
    );

    var comment = File(report.commentPath).readAsStringSync();
    expect(comment, contains('against `master`'));
    expect(comment, contains('1 changed'));
    expect(comment, contains('| `demo/card.dart#card` | changed |'));
    expect(comment, contains('100.00% · 1 region'));
    expect(comment, contains(mosaicUrlPlaceholder));
    expect(comment, contains(viewerUrlPlaceholder));

    var mosaic = img.decodePng(File(report.mosaicPath!).readAsBytesSync())!;
    expect(mosaic.width, greaterThan(0));
    expect(mosaic.height, greaterThan(0));
  });

  test("a scenario's face in the mosaic is its worst step with frames", () {
    var framePath = p.join(temp.path, 'pay.raw');
    File(framePath)
        .writeAsBytesSync(Uint8List(4 * 4 * 4)..fillRange(0, 4 * 4 * 4, 120));
    var report = writePrReport(
      artifact: ComparisonArtifact(
        previews: previews(const []),
        scenarios: ScenarioResults.of(
          ran: 1,
          skipped: 0,
          elapsed: const Duration(seconds: 1),
          items: [
            ScenarioComparison(
              scenario: 'test/shop.dart#Checkout',
              state: ComparedState.changed,
              items: const [
                ComparedItem(id: 'guest › Pay', state: ComparedState.changed),
              ],
              branches: const [],
              frames: {
                'guest › Pay': (
                  base: null,
                  head: FrameRef(path: framePath, width: 4, height: 4),
                ),
              },
            ),
          ],
        ),
      ),
      cache: cache,
      against: 'develop',
      directory: p.join(temp.path, 'report'),
    );

    var comment = File(report.commentPath).readAsStringSync();
    expect(comment, contains('| `test/shop.dart#Checkout` | changed |'));
    expect(comment, contains('step `guest › Pay`'));
    expect(report.mosaicPath, isNotNull);
  });
}
