

import 'package:flutterware/drawing.dart';

class PathBuilder {
  final List<PathCommand> commands;

  PathBuilder(this.commands);
}

abstract class PathCommand {}

class MoveTo implements PathCommand {
  final double x, y;

  MoveTo(this.x, this.y);
}

class LineTo implements PathCommand {
  final double x, y;

  LineTo(this.x, this.y);
}

class CubicTo implements PathCommand {
  final double x, y;

  CubicTo(this.x, this.y);
}

class Close implements PathCommand {

}