import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rectangle.g.dart';

abstract class Rectangle implements Built<Rectangle, RectangleBuilder> {
  static Serializer<Rectangle> get serializer => _$rectangleSerializer;

  Rectangle._();
  factory Rectangle._builder([void Function(RectangleBuilder) updates]) =
      _$Rectangle;

  factory Rectangle(
      {double? left, double? top, double? right, double? bottom}) {
    return Rectangle._builder(
      (b) => b
        ..left = left ?? 0
        ..top = top ?? 0
        ..right = right ?? 0
        ..bottom = bottom ?? 0,
    );
  }

  factory Rectangle.fromLTRB(
      double left, double top, double right, double bottom) {
    return Rectangle._builder((b) => b
      ..left = left
      ..top = top
      ..right = right
      ..bottom = bottom);
  }

  factory Rectangle.fromTLWH(
      double top, double left, double width, double height) {
    return Rectangle._builder((b) => b
      ..left = left
      ..top = top
      ..right = left + width
      ..bottom = top + height);
  }

  double get left;

  double get top;

  double get right;

  double get bottom;

  double get width => right - left;

  double get height => bottom - top;
}
