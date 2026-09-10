// A gradient paint as the engine takes it.
//
// Its own file because two painters will want it — a text pass today, and a
// frame's fill the day `fill` becomes a list of paints (master plan §6) — and
// because every rule the engine has about gradients is kept here rather than
// at each call. dart:ui throws on a gradient with no stops unless it has
// exactly two colours, so the even spread the model promises is spelled out
// before the engine sees it.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'core/values.dart';
import 'flutter_bridge.dart';

/// [g] measured against [box], every colour faded by [opacity].
///
/// Needs two colours at least. A caller with fewer paints a solid instead:
/// a gradient of one colour is that colour, and the engine is not asked.
ui.Shader sceneGradientShader(SceneGradient g, Rect box, {double opacity = 1}) {
  var colors = [
    for (var c in g.colors)
      opacity == 1
          ? c.flutter
          : c.flutter.withValues(alpha: c.flutter.a * opacity),
  ];
  var stops = g.resolvedStops;
  return switch (g) {
    LinearPaint(:var begin, :var end) => ui.Gradient.linear(
      Alignment(begin.x, begin.y).withinRect(box),
      Alignment(end.x, end.y).withinRect(box),
      colors,
      stops,
    ),
  };
}
