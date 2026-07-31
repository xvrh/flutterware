import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog_guest.dart';

/// Draws a box around one node, and its type above it — the inspector's
/// rectangle, painted **inside a surface that is the guest's logical size**:
/// node rects are in the guest's own coordinates, so in that box the painter
/// needs no transform and inherits whatever `FittedBox` or device frame sits
/// above it.
///
/// The catalog's live preview keeps its own painter (it prefers the guest's
/// last-frame box over the tree's, which only means something with a live
/// guest); this is the snapshot half, for surfaces where the tree's geometry
/// *is* the picture's — a scenario step capture.
class NodeHighlightPainter extends CustomPainter {
  NodeHighlightPainter({required this.node, required this.color});

  final InspectNode? node;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (node?.layout case var layout?) {
      var rect = Rect.fromLTWH(layout.x, layout.y, layout.width, layout.height);
      canvas
        ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.18))
        ..drawRect(
          rect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );

      // The type, because a rectangle alone does not say which of the four
      // boxes stacked at this corner you have got.
      var label = TextPainter(
        text: TextSpan(
          text: ' ${node!.type} ',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Above the box, or inside it when there is no room above — a label off
      // the top of the picture names nothing.
      var top = rect.top >= label.height ? rect.top - label.height : rect.top;
      var left = rect.left
          .clamp(0.0, math.max(0.0, size.width - label.width))
          .toDouble();
      canvas.drawRect(
        Rect.fromLTWH(left, top, label.width, label.height),
        Paint()..color = color,
      );
      label.paint(canvas, Offset(left, top));
    }
  }

  @override
  bool shouldRepaint(NodeHighlightPainter old) =>
      old.node?.id != node?.id ||
      old.node?.layout != node?.layout ||
      old.color != color;
}
