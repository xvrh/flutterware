import 'dart:ui';
import 'package:flutter/widgets.dart';

class FakeWindowPadding implements WindowPadding {
  FakeWindowPadding(EdgeInsets? padding)
      : bottom = padding?.bottom ?? 0,
        left = padding?.left ?? 0,
        right = padding?.right ?? 0,
        top = padding?.top ?? 0;

  @override
  final double bottom;

  @override
  final double left;

  @override
  final double right;

  @override
  final double top;
}
