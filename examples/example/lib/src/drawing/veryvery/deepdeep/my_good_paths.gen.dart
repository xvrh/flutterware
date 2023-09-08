//@flutterware:drawing=1.0

import 'package:flutterware/drawing.dart';

// [mockup] path="pasted_images/xxx.png" x=0 y=0 w=200 h=100
// [mockup] path="pasted_images/yyy.png" x=1000.1 y=0 w=200 h=100 opacity=0.4
// [preview] stroke=2
final myPath = PathBuilder([
  MoveTo(0, 0),
  LineTo(200, 20),
  LineTo(270, 100),
  LineTo(50, 270),
  LineTo(10, 270),
  LineTo(-100, 170),
  Close(),
]);
