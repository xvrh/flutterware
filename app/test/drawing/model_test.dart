

import 'package:flutterware_app/src/drawing/model/file.dart';
import 'package:test/test.dart';

void main() {
  test('Parse DrawingFile', () {
    var file = DrawingFile.parse('''
import 'package:flutterware/drawing.dart';

// #mockup: path=”pasted_images/xxx.png”,x=0,y=0,w=200,h=100
// #preview: stroke=2, color=#124578
final myPath = PathBuilder(<PathElement>[
  MoveTo(0, 2),
  LineTo(3, 5),
  Close(),
]);
''');

  });
}