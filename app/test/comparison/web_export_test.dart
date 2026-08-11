import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutterware_app/src/comparison/shot_cache.dart';
import 'package:flutterware_app/src/comparison/web_export.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Everything after the compile — which is where all the logic is — without a
/// toolchain and a minute of `flutter build web`. The same seam the scenario
/// exporter's test uses, for the same reason.
void main() {
  late Directory temp;
  late ShotCache cache;
  late ComparisonWebExporter exporter;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fw_comparison_export');
    cache = ShotCache(p.join(temp.path, 'shots'));
    exporter =
        ComparisonWebExporter(
            flutterExecutable: 'flutter-not-invoked',
            appToolRoot: temp.path,
          )
          ..debugCompile = (arguments) async {
            // What a real build leaves behind: an index.html with a base tag.
            var viewer = Directory(
              p.join(temp.path, 'build', 'comparison_web_viewer'),
            )..createSync(recursive: true);
            File(
              p.join(viewer.path, 'index.html'),
            ).writeAsStringSync('<base href="/">\n<title>Comparison</title>');
            File(
              p.join(viewer.path, 'main.dart.js'),
            ).writeAsStringSync('// js');
            return 0;
          };
  });

  tearDown(() => temp.deleteSync(recursive: true));

  void file(String key, int value, {int width = 4, int height = 4}) {
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

  String writeFrame(String name, int value, {int width = 4, int height = 4}) {
    var path = p.join(temp.path, 'run', name);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        Uint8List(width * height * 4)..fillRange(0, width * height * 4, value),
      );
    return path;
  }

  Map<String, Object?> index({String? framePath}) => {
    'base': 'abc123def456',
    'head': '/work/tree',
    'previews': {
      'items': [
        {
          'id': 'demo/card.dart#card',
          'state': 'changed',
          'shots': {'base': 'k-base', 'head': 'k-head'},
        },
      ],
    },
    if (framePath != null)
      'scenarios': {
        'items': [
          {
            'id': 'test/shop.dart#Checkout',
            'state': 'changed',
            'steps': [
              {
                'id': 'guest › Pay',
                'state': 'changed',
                'frames': {
                  'head': {'path': framePath, 'width': 4, 'height': 4},
                },
              },
            ],
          },
        ],
      },
  };

  test('the page holds the viewer, the index and a PNG per frame', () async {
    file('k-base', 40);
    file('k-head', 200);
    var frame = writeFrame('pay.raw', 120);

    var out = p.join(temp.path, 'page');
    var export = await exporter.export(
      index: index(framePath: frame),
      cache: cache,
      against: 'master',
      output: out,
    );

    expect(File(p.join(out, 'index.html')).existsSync(), isTrue);
    expect(export.frames, 3);

    var written =
        jsonDecode(File(p.join(out, 'index.json')).readAsStringSync())
            as Map<String, Object?>;
    expect(written['against'], 'master');

    // The preview row's cache keys became relative paths…
    var item =
        (((written['previews']! as Map)['items'] as List).single
                as Map)['shots']
            as Map;
    expect(item['base'], 'shots/k-base.png');
    expect(item['head'], 'shots/k-head.png');
    // …that resolve to real, decodable PNGs.
    var png = File(p.join(out, 'shots', 'k-head.png'));
    expect(png.existsSync(), isTrue);
    var decoded = img.decodePng(png.readAsBytesSync())!;
    expect(decoded.width, 4);

    // The scenario step's absolute path became a page-relative PNG too.
    var step =
        ((((written['scenarios']! as Map)['items'] as List).single
                        as Map)['steps']
                    as List)
                .single
            as Map;
    var head = (step['frames'] as Map)['head'] as Map;
    expect(head['path'], 'frames/s0/pay.png');
    expect(File(p.join(out, 'frames', 's0', 'pay.png')).existsSync(), isTrue);
  });

  test('a frame the cache no longer has stays a key, honestly', () async {
    file('k-base', 40);
    // k-head was never filed — evicted, say.

    var out = p.join(temp.path, 'page');
    await exporter.export(
      index: index(),
      cache: cache,
      against: 'master',
      output: out,
    );

    var written =
        jsonDecode(File(p.join(out, 'index.json')).readAsStringSync())
            as Map<String, Object?>;
    var shots =
        (((written['previews']! as Map)['items'] as List).single
                as Map)['shots']
            as Map;
    expect(shots['base'], 'shots/k-base.png');
    // The page will 404 on it and say nothing rendered — nearer the truth
    // than silently dropping the reference.
    expect(shots['head'], 'k-head');
  });

  test('one key referenced twice is encoded once', () async {
    file('k-base', 40);
    var doubled = index();
    ((doubled['previews']! as Map)['items'] as List).add({
      'id': 'demo/card.dart#again',
      'state': 'same',
      'shots': {'base': 'k-base', 'head': 'k-base'},
    });

    var out = p.join(temp.path, 'page');
    var export = await exporter.export(
      index: doubled,
      cache: cache,
      against: 'master',
      output: out,
    );

    expect(export.frames, 1);
  });

  test('a base href points the page at its mount', () async {
    var out = p.join(temp.path, 'page');
    await exporter.export(
      index: index(),
      cache: cache,
      against: 'master',
      output: out,
      baseHref: '/pr-42/comparison/',
    );

    expect(
      File(p.join(out, 'index.html')).readAsStringSync(),
      contains('<base href="/pr-42/comparison/">'),
    );
  });
}
