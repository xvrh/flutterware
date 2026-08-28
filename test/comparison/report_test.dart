import 'dart:convert';
import 'dart:io';

import 'package:flutterware/comparison_report.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The disk half — what a consumer's `tool/` script actually calls.
///
/// The round trip against the writer lives in `app/`, where the writer is.
/// This is the reader on its own: what it does with a directory that holds no
/// report, and the one distinction it exists to enforce — an exported page's
/// frames can be opened, and the comparison cache's cannot.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fw_report'));
  tearDown(() => root.deleteSync(recursive: true));

  /// A page holding [json] as its `index.json`, and [frames] beside it.
  String page(
    String name,
    Map<String, Object?> json, {
    List<String> frames = const [],
  }) {
    var dir = Directory(p.join(root.path, name))..createSync(recursive: true);
    File(p.join(dir.path, comparisonReportFile))
        .writeAsStringSync(jsonEncode(json));
    for (var frame in frames) {
      File(p.join(dir.path, frame.replaceAll('/', p.separator)))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(const [0x89, 0x50, 0x4e, 0x47]);
    }
    return dir.path;
  }

  Map<String, Object?> index({required String frames, String? shot}) => {
    'version': comparisonReportVersion,
    'base': 'abc123def456',
    'frames': frames,
    'counts': {'changed': 1},
    'previews': {
      'rendered': 2,
      'ms': 178,
      'items': [
        {
          'id': 'demo/card.dart#card',
          'state': 'changed',
          'shots': {'base': shot ?? 'k-base', 'head': shot ?? 'k-head'},
        },
      ],
    },
  };

  test('a directory with no report says what to run', () async {
    var empty = Directory(p.join(root.path, 'nothing'))..createSync();

    expect(
      () => ComparisonReport.read(empty.path),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains(comparisonReportFile), contains('fw compare')),
        ),
      ),
    );
  });

  test('a report from a newer flutterware is refused, not half-read', () {
    var future = page('future', {
      ...index(frames: 'relative'),
      'version': comparisonReportVersion + 1,
    });

    expect(
      () => ComparisonReport.read(future),
      throwsA(isA<FormatException>()),
    );
  });

  group('an exported page', () {
    test('resolves a frame beside its index', () async {
      var dir = page(
        'web',
        index(frames: 'relative', shot: 'shots/k-head.png'),
        frames: ['shots/k-head.png'],
      );
      var report = await ComparisonReport.read(dir);

      expect(report.index.frames, ComparisonFrames.relative);
      expect(
        report.frame('shots/k-head.png')!.path,
        p.join(dir, 'shots', 'k-head.png'),
      );
    });

    // An export encodes what the shot cache still held. A frame evicted
    // before it ran keeps its original reference — a bare cache key for a
    // preview, an absolute path to a raw frame for a scenario step — and the
    // page 404s on it. Composing a path anyway would hand a script a `File`
    // that is not there, which reads exactly like one it has not written yet.
    test(
      'a frame the export could not write is absent, not a bad path',
      () async {
        var report = await ComparisonReport.read(
          page('web', index(frames: 'relative', shot: 'k-head')),
        );

        expect(report.index.frames, ComparisonFrames.relative);
        expect(report.frame('k-head'), isNull);
      },
    );

    test('an absolute reference is never this page to open', () async {
      var stray = File(p.join(root.path, 'elsewhere.raw'))
        ..writeAsBytesSync(const [0, 1, 2, 3]);
      var report = await ComparisonReport.read(
        page('web', index(frames: 'relative', shot: stray.path)),
      );

      // It exists — this is the machine that produced it — and it is still
      // not the PNG beside the page that `frame` claims to hand back.
      expect(stray.existsSync(), isTrue);
      expect(report.frame(stray.path), isNull);
    });

    test('the findings carry their rows', () async {
      var report = await ComparisonReport.read(
        page('web', index(frames: 'relative')),
      );

      expect(report.index.ok, isFalse);
      expect(report.index.findings.single.id, 'demo/card.dart#card');
      expect(report.index.findings.single.half, ComparedHalfKind.previews);
      expect(report.index.previewsHalf.worked, 2);
    });
  });

  // The cache's own copy holds the same verdict and frames nothing outside
  // that machine can open: `ShotCache` keys, and headerless raw frames. It is
  // worth reading for the verdict; asking it for a picture is the mistake
  // this refuses.
  group('the comparison cache', () {
    test('gives up its verdict', () async {
      var report = await ComparisonReport.read(
        page('cache', index(frames: 'local')),
      );

      expect(report.index.frames, ComparisonFrames.local);
      expect(report.index.findings.single.state, ComparedState.changed);
    });

    test(
      'refuses a frame, and names the flag that would produce one',
      () async {
        var report = await ComparisonReport.read(
          page('cache', index(frames: 'local')),
        );

        expect(
          () => report.frame('k-head'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('k-head'), contains('--report=')),
            ),
          ),
        );
      },
    );
  });
}
