import 'dart:io';

import 'package:flutterware_app/src/motion/filmstrip.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

img.Image _cell(int width, int height) {
  var image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 40, 40));
  return image;
}

void main() {
  group('where the frames are taken', () {
    test('both ends are included, always', () {
      // A strip whose first frame is not t=0 cannot show what a motion starts
      // from, and one whose last is not t=1 cannot show where it lands.
      for (var count in [2, 3, 5, 9]) {
        var stops = filmstripStops(count);
        expect(stops, hasLength(count), reason: '$count');
        expect(stops.first, 0, reason: '$count');
        expect(stops.last, 1, reason: '$count');
      }
    });

    test('evenly spaced', () {
      expect(filmstripStops(5), [0, 0.25, 0.5, 0.75, 1]);
    });

    test('one frame is the end, not the start', () {
      expect(filmstripStops(1), [1]);
    });
  });

  group('composing', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('filmstrip'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lays frames out side by side with room for the labels', () {
      var frames = [
        for (var t in filmstripStops(3))
          FilmstripFrame(image: _cell(640, 480), t: t, ms: (t * 900).round()),
      ];
      var output = p.join(dir.path, 'strip.png');
      var sheet = img.decodePng(
        composeFilmstrip(
          frames,
          output: output,
          cellWidth: 200,
        ).readAsBytesSync(),
      )!;

      // Three 200px cells, four gutters.
      expect(sheet.width, 3 * 200 + 4 * 8);
      // 480 scaled to a 200 width is 150 tall, plus the label bar and margins.
      expect(sheet.height, 150 + 20 + 16);
    });

    test('scales down, never up', () {
      // A frame rendered small and enlarged is a blurrier frame, and the sheet
      // is for judging timing rather than pixels.
      var frames = [FilmstripFrame(image: _cell(80, 60), t: 1, ms: 900)];
      var sheet = img.decodePng(
        composeFilmstrip(
          frames,
          output: p.join(dir.path, 's.png'),
          cellWidth: 300,
        ).readAsBytesSync(),
      )!;
      expect(sheet.width, 80 + 2 * 8);
    });

    test('refuses an empty strip rather than writing a blank image', () {
      expect(
        () => composeFilmstrip(const [], output: p.join(dir.path, 'x.png')),
        throwsArgumentError,
      );
    });
  });
}
