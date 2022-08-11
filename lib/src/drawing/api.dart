import 'dart:ui';

class PathBuilder {
  final List<PathCommand> commands;

  PathBuilder(this.commands);

  Path build() {
    var path = Path();
    for (var command in commands) {
      command.applyTo(path);
    }
    return path;
  }
}

abstract class PathCommand {
  void applyTo(Path path);
}

class MoveTo implements PathCommand {
  final double x, y;

  const MoveTo(this.x, this.y);

  @override
  void applyTo(Path path) {
    path.moveTo(x, y);
  }

  @override
  String toString() => 'MoveTo($x, $y)';
}

class LineTo implements PathCommand {
  final double x, y;

  const LineTo(this.x, this.y);

  @override
  void applyTo(Path path) {
    path.lineTo(x, y);
  }

  @override
  String toString() => 'LineTo($x, $y)';
}

class CubicTo implements PathCommand {
  final double x1, y1;
  final double x2, y2;
  final double x3, y3;

  const CubicTo(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3);

  @override
  void applyTo(Path path) {
    path.cubicTo(x1, y1, x2, y2, x3, y3);
  }

  @override
  String toString() => 'CubicTo($x1, $y1, $x2, $y2, $x3, $y3)';
}

class RelativeCubicTo implements PathCommand {
  final double x1, y1;
  final double x2, y2;
  final double x3, y3;

  const RelativeCubicTo(this.x1, this.y1, this.x2, this.y2, this.x3, this.y3);

  @override
  void applyTo(Path path) {
    path.relativeCubicTo(x1, y1, x2, y2, x3, y3);
  }

  @override
  String toString() => 'RelativeCubicTo($x1, $y1, $x2, $y2, $x3, $y3)';
}

class QuadraticBezierTo implements PathCommand {
  final double x1, y1, x2, y2;

  const QuadraticBezierTo(this.x1, this.y1, this.x2, this.y2);

  @override
  void applyTo(Path path) {
    path.quadraticBezierTo(x1, y1, x2, y2);
  }

  @override
  String toString() => 'QuadraticBezierTo($x1, $y1, $x2, $y2)';
}

class RelativeQuadraticBezierTo implements PathCommand {
  final double x1, y1, x2, y2;

  const RelativeQuadraticBezierTo(this.x1, this.y1, this.x2, this.y2);

  @override
  void applyTo(Path path) {
    path.relativeQuadraticBezierTo(x1, y1, x2, y2);
  }

  @override
  String toString() => 'RelativeQuadraticBezierTo($x1, $y1, $x2, $y2)';
}

class ArcToPoint implements PathCommand {
  final double x, y;
  final Radius radius;
  final double rotation;
  final bool largeArc;
  final bool clockwise;

  const ArcToPoint(
    this.x,
    this.y, {
    required this.radius,
    required this.rotation,
    required this.largeArc,
    required this.clockwise,
  });

  @override
  void applyTo(Path path) {
    path.arcToPoint(
      Offset(x, y),
      clockwise: clockwise,
      largeArc: largeArc,
      radius: radius,
    );
  }

  @override
  String toString() => 'ArcToPoint($x, $y, radius: $radius, '
      'rotation: $rotation, '
      'largeArc: $largeArc, clockwise:$clockwise)';
}

class RelativeArcToPoint implements PathCommand {
  final double x, y;
  final Radius radius;
  final double rotation;
  final bool largeArc;
  final bool clockwise;

  const RelativeArcToPoint(
    this.x,
    this.y, {
    required this.radius,
    required this.rotation,
    required this.largeArc,
    required this.clockwise,
  });

  @override
  void applyTo(Path path) {
    path.relativeArcToPoint(
      Offset(x, y),
      clockwise: clockwise,
      largeArc: largeArc,
      radius: radius,
    );
  }

  @override
  String toString() => 'RelativeArcToPoint($x, $y, radius: $radius, '
      'rotation: $rotation, '
      'largeArc: $largeArc, clockwise:$clockwise)';
}

class Close implements PathCommand {
  const Close();

  @override
  void applyTo(Path path) {
    path.close();
  }

  @override
  String toString() => 'Close()';
}
