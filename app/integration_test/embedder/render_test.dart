import 'dart:io';

import 'package:image/image.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('renders scene.dart to an 800x600 PNG', () async {
    // `dart test` runs with the package root (<app>) as the current directory.
    var runScript =
        p.join(Directory.current.path, 'tool', 'embedder', 'run.dart');

    var result =
        await Process.run(Platform.resolvedExecutable, ['run', runScript]);

    printOnFailure('exit code: ${result.exitCode}');
    printOnFailure('stdout:\n${result.stdout}');
    printOnFailure('stderr:\n${result.stderr}');
    expect(result.exitCode, 0);

    var pngFile =
        File(p.join(Directory.current.path, 'build', 'embedder', 'scene.png'));
    expect(pngFile.existsSync(), isTrue, reason: 'scene.png should exist');

    var image = decodePng(pngFile.readAsBytesSync())!;
    expect(image.width, 800);
    expect(image.height, 600);

    // The Scaffold background is Color(0xFF1565C0): R=21 G=101 B=192.
    // A wrong channel order (RGBA vs BGRA) makes this fail loudly.
    var corner = image.getPixel(2, 2);
    expect(corner.r.toInt(), closeTo(21, 4));
    expect(corner.g.toInt(), closeTo(101, 4));
    expect(corner.b.toInt(), closeTo(192, 4));

    // The centred white text means the central scanline is not all background.
    var sawText = false;
    for (var x = 100; x < 700 && !sawText; x += 3) {
      var px = image.getPixel(x, 300);
      if (px.r.toInt() > 200 && px.g.toInt() > 200 && px.b.toInt() > 200) {
        sawText = true;
      }
    }
    expect(sawText, isTrue,
        reason: 'expected white text pixels along the centre scanline');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
