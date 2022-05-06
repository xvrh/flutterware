import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'arrow_path.dart';
import 'core/matrix.dart';
import 'graphite.dart';

class Edge {
  final List<Offset> points;
  final MatrixNode from;
  final MatrixNode to;

  Edge(this.points, this.from, this.to);
}

enum Direction { top, bottom, left, right }

Direction getXVertexDirection(int x1, int x2) {
  return x1 < x2 ? Direction.right : Direction.left;
}

Direction getYVertexDirection(int y1, int y2) {
  return y1 < y2 ? Direction.bottom : Direction.top;
}

Direction getVectorDirection(int x1, int y1, int x2, int y2) {
  return y1 == y2 ? getXVertexDirection(x1, x2) : getYVertexDirection(y1, y2);
}

double getMargin(AnchorMargin margin, double distance) {
  if (margin == AnchorMargin.none) return 0;
  return margin == AnchorMargin.start ? -distance : distance;
}

Offset getCellCenter(Size cellSize, double padding, double cellX, double cellY,
    double distance, AnchorMargin margin, MatrixOrientation orientation) {
  var outset = getMargin(margin, distance);
  var x = cellX * cellSize.width + padding * cellX + cellSize.width * 0.5;
  var y = cellY * cellSize.height + padding * cellY + cellSize.height * 0.5;
  if (orientation == MatrixOrientation.horizontal) {
    x += outset;
  } else {
    y += outset;
  }
  return Offset(x, y);
}

Offset getCellEntry(
    Direction direction,
    Size cellSize,
    double padding,
    double cellX,
    double cellY,
    double distance,
    AnchorMargin margin,
    MatrixOrientation orientation) {
  switch (direction) {
    case Direction.top:
      var x = getCellCenter(
              cellSize, padding, cellX, cellY, distance, margin, orientation)
          .dx;
      var y = cellY * cellSize.height + padding * cellY;
      return Offset(x, y);
    case Direction.bottom:
      var x = getCellCenter(
              cellSize, padding, cellX, cellY, distance, margin, orientation)
          .dx;
      var y = (cellY + 1) * cellSize.height + padding * cellY;
      return Offset(x, y);
    case Direction.right:
      var y = getCellCenter(
              cellSize, padding, cellX, cellY, distance, margin, orientation)
          .dy;
      var x = (cellX + 1) * cellSize.width + padding * cellX;
      return Offset(x, y);
    case Direction.left:
      var y = getCellCenter(
              cellSize, padding, cellX, cellY, distance, margin, orientation)
          .dy;
      var x = cellX * cellSize.width + (padding * cellX);
      return Offset(x, y);
  }
}

Offset getPointWithResolver(
    Direction direction,
    Size cellSize,
    double padding,
    double distance,
    MatrixNode item,
    AnchorMargin margin,
    MatrixOrientation orientation) {
  if (item.isAnchor) {
    return getCellCenter(cellSize, padding, item.x.toDouble(),
        item.y.toDouble(), distance, margin, orientation);
  } else {
    return getCellEntry(direction, cellSize, padding, item.x.toDouble(),
        item.y.toDouble(), distance, margin, orientation);
  }
}

Paint _defaultPaintBuilder(Edge edge) {
  return Paint()
    ..color = Color(0xFF000000)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 2;
}

typedef EdgePaintBuilder = Paint Function(Edge edge);

typedef EdgePathBuilder = Path Function(List<Offset> points);

class LinesPainter extends CustomPainter {
  final Map<String, MatrixNode> matrixMap;
  final DirectGraph config;
  final BuildContext context;

  Path _defaultEdgePathBuilder(List<Offset> points) {
    var path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    points.sublist(1).forEach((p) => path.lineTo(p.dx, p.dy));
    return ArrowPath.make(
        path: path, tipLength: config.tipLength, tipAngle: config.tipAngle);
  }

  List<Edge> collectEdges(MatrixNode node, Map<String, MatrixNode> edges) {
    return node.renderIncomes.map((i) => edges[i]).fold([],
        (List<Edge> acc, MatrixNode? income) {
      var points = <Offset>[];
      var incomeNode = edges[income!.id];
      var startNode = node;
      var margins = getEdgeMargins(startNode, incomeNode!);
      var nodeMargin = margins[0];
      var incomeMargin = margins[1];
      var direction = getVectorDirection(
          startNode.x, startNode.y, incomeNode.x, incomeNode.y);
      var directions = pointResolversMap[direction]!;
      var from = directions[0], to = directions[1];
      var startPoint = getPointWithResolver(
          from,
          config.cellSize,
          config.cellPadding,
          config.contactEdgesDistance,
          startNode,
          nodeMargin,
          config.orientation);
      points.add(startPoint);
      while (incomeNode!.isAnchor) {
        margins = getEdgeMargins(startNode, incomeNode);
        nodeMargin = margins[0];
        incomeMargin = margins[1];
        direction = getVectorDirection(
            startNode.x, startNode.y, incomeNode.x, incomeNode.y);
        directions = pointResolversMap[direction]!;
        from = directions[0];
        to = directions[1];
        points.add(getPointWithResolver(
            to,
            config.cellSize,
            config.cellPadding,
            config.contactEdgesDistance,
            incomeNode,
            incomeMargin,
            config.orientation));
        startNode = incomeNode;
        incomeNode = edges[incomeNode.renderIncomes[0]];
      }
      margins = getEdgeMargins(startNode, incomeNode);
      nodeMargin = margins[0];
      incomeMargin = margins[1];
      direction = getVectorDirection(
          startNode.x, startNode.y, incomeNode.x, incomeNode.y);
      directions = pointResolversMap[direction]!;
      from = directions[0];
      to = directions[1];
      points.add(getPointWithResolver(
          to,
          config.cellSize,
          config.cellPadding,
          config.contactEdgesDistance,
          incomeNode,
          incomeMargin,
          config.orientation));
      acc.add(Edge(points, incomeNode, node));
      return acc;
    });
  }

  const LinesPainter(this.context, this.config, this.matrixMap);

  @override
  void paint(Canvas canvas, Size size) {
    var edges = <Edge>[];
    matrixMap.forEach((key, value) {
      if (value.isAnchor) return;
      edges.addAll(collectEdges(value, matrixMap));
    });
    for (var e in edges) {
      var points = e.points.reversed.toList();
      var pathBuilder = config.pathBuilder;
      var paintBuilder = config.paintBuilder;
      var path = pathBuilder == null
          ? _defaultEdgePathBuilder(points)
          : pathBuilder(points);
      final paint =
          paintBuilder == null ? _defaultPaintBuilder(e) : paintBuilder(e);
      canvas.drawPath(
        path,
        paint,
      );

      var tooltip = config.edgeTooltip?.call(e.from.id, e.to.id);
      if (tooltip != null) {
        var a = points[points.length - 2];
        var b = points[points.length - 1];
        var paragraphBuilder =
            ParagraphBuilder(ParagraphStyle(textAlign: TextAlign.center));
        paragraphBuilder.pushStyle(tooltip.style.getTextStyle());
        paragraphBuilder.addText(tooltip.text);
        var paragraph = paragraphBuilder.build();
        var rect = Rect.fromPoints(a, b);
        paragraph.layout(ParagraphConstraints(width: rect.width));
        canvas.drawParagraph(
            paragraph, rect.centerLeft - Offset(0, paragraph.height + 5));
      }
    }
  }

  @override
  bool shouldRepaint(LinesPainter oldDelegate) {
    return true;
  }
}

List<AnchorMargin> getEdgeMargins(MatrixNode node, MatrixNode income) {
  if (node.isAnchor && income.isAnchor) {
    return [node.anchorMargin!, income.anchorMargin!];
  } else if (node.isAnchor) {
    return [node.anchorMargin!, node.anchorMargin!];
  } else if (income.isAnchor) {
    return [income.anchorMargin!, income.anchorMargin!];
  } else {
    return [AnchorMargin.none, AnchorMargin.none];
  }
}

Offset applyMargin(AnchorMargin margin, Offset point, double distance,
    MatrixOrientation orientation) {
  if (margin == AnchorMargin.none) return point;
  if (orientation == MatrixOrientation.horizontal &&
      margin == AnchorMargin.start) {
    return Offset(point.dx - distance, point.dy);
  }
  if (orientation == MatrixOrientation.vertical &&
      margin == AnchorMargin.start) {
    return Offset(point.dx, point.dy - distance);
  }
  if (orientation == MatrixOrientation.horizontal &&
      margin == AnchorMargin.end) {
    return Offset(point.dx + distance, point.dy);
  }
  if (orientation == MatrixOrientation.vertical && margin == AnchorMargin.end) {
    return Offset(point.dx, point.dy + distance);
  }
  return point;
}

const pointResolversMap = {
  Direction.top: [Direction.top, Direction.bottom],
  Direction.bottom: [Direction.bottom, Direction.top],
  Direction.right: [Direction.right, Direction.left],
  Direction.left: [Direction.left, Direction.right]
};
