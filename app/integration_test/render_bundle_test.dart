@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutterware_app/src/embedder/flutter_cache.dart';
import 'package:flutterware_app/src/render_bundle/bundle_builder.dart';
import 'package:flutterware_render/client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The whole render transport, as real processes: a bundle built from the
/// example app's registrar, then a [RenderPool] driving the spawned
/// `flutter_tester` guest — the same loop a server runs in its container.
///
/// ```sh
/// cd app && dart test integration_test/render_bundle_test.dart
/// ```
void main() {
  // The server side of the contract. In a real deployment these descriptors
  // live in a pure-Dart package shared with the app; here they mirror
  // `examples/example/lib/renders.dart` with raw-map args.
  final monthlyChart = WidgetRender<Map<String, Object?>>(
    'charts/monthly',
    encodeArgs: (args) => args,
    decodeArgs: (json) => json,
  );
  final chartReport = DocumentRender<Map<String, Object?>>(
    'reports/chart',
    encodeArgs: (args) => args,
    decodeArgs: (json) => json,
  );
  final chartArgs = {
    'title': 'Devices over time',
    'values': [30.0, 60.0, 45.0, 80.0],
  };

  late Directory outDir;
  late RenderPool pool;
  final logs = <String>[];

  setUpAll(() async {
    var exampleRoot = p.normalize(
      p.absolute(p.join('..', 'examples', 'example')),
    );
    expect(Directory(exampleRoot).existsSync(), isTrue, reason: exampleRoot);
    outDir = Directory.systemTemp.createTempSync('fw_render_bundle_test');
    var manifest = await buildRenderBundle(
      packageRoot: exampleRoot,
      target: 'lib/renders.dart',
      output: outDir.path,
      cache: FlutterCache.fromRunningSdk(),
      log: logs.add,
    );
    expect(manifest.fonts, isNotEmpty, reason: 'Roboto is declared');
    pool = await RenderPool.start(bundle: outDir.path, onGuestLog: logs.add);
  });

  tearDownAll(() async {
    await pool.close();
    try {
      outDir.deleteSync(recursive: true);
    } catch (_) {
      // A killed guest may briefly hold the directory open.
    }
  });

  test('the bundle is self-contained', () {
    expect(File(p.join(outDir.path, 'manifest.json')).existsSync(), isTrue);
    for (var entity in outDir.listSync(recursive: true, followLinks: false)) {
      expect(entity is Link, isFalse, reason: '${entity.path} is a symlink');
    }
  });

  test('the guest announces its points', () {
    expect(pool.points.map((point) => point.name), {
      'charts/monthly',
      'reports/chart',
    });
    expect(
      pool.points.singleWhere((point) => point.name == 'reports/chart').kind,
      RenderPointKind.document,
    );
  });

  test('a widget render comes back as SVG with real text', () async {
    var svg = await pool.svg(
      monthlyChart,
      chartArgs,
      size: const RenderSize(400, 200),
    );
    expect(svg.text, contains('<svg'));
    expect(svg.text, contains('Devices over time'));
  });

  test('the same widget entry renders as PNG and as a PDF page', () async {
    var png = await pool.png(
      monthlyChart,
      chartArgs,
      size: const RenderSize(400, 200),
      pixelRatio: 2,
    );
    expect(png.bytes.take(4), [0x89, 0x50, 0x4E, 0x47]);

    var page = await pool.pdfPage(
      monthlyChart,
      chartArgs,
      size: const RenderSize(400, 200),
    );
    expect(String.fromCharCodes(page.bytes.take(5)), '%PDF-');
  });

  test('a document render composes its own PDF', () async {
    var report = await pool.pdf(chartReport, chartArgs);
    expect(String.fromCharCodes(report.bytes.take(5)), '%PDF-');
    expect(report.bytes.length, greaterThan(1000));
  });

  test('an unknown point fails with the catalogue in the message', () async {
    var missing = WidgetRender<Map<String, Object?>>(
      'charts/nope',
      encodeArgs: (args) => args,
      decodeArgs: (json) => json,
    );
    await expectLater(
      pool.svg(
        missing,
        const <String, Object?>{},
        size: const RenderSize(10, 10),
      ),
      throwsA(
        isA<RenderException>().having(
          (e) => e.message,
          'message',
          contains('charts/monthly'),
        ),
      ),
    );
  });
}
