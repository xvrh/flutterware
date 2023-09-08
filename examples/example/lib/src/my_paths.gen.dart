//@flutterware:drawing=1.0

import 'package:flutterware/drawing.dart';

// [mockup] path="pasted_images/xxx.png" x=0 y=0 w=200 h=100
// [mockup] path="pasted_images/yyy.png" x=1000.1 y=0 w=200 h=100 opacity=0.4
// [preview] stroke=2
final myPath = PathBuilder([
  MoveTo(0.545, 2),
  LineTo(3, 5.3),
  Close(),
]);
