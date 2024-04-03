import 'package:flutter/widgets.dart';
import 'core/matrix.dart';
import 'graphite.dart';

class GraphiteEdges extends StatefulWidget {
  final Widget child;
  final Matrix matrix;

  const GraphiteEdges({
    super.key,
    required this.child,
    required this.matrix,
  });

  @override
  State<GraphiteEdges> createState() => _GraphiteEdgesState();
}

class _GraphiteEdgesState extends State<GraphiteEdges> {
  @override
  Widget build(BuildContext context) {
    var config = context.findAncestorWidgetOfExactType<DirectGraph>()!;
    return config.interactiveBuilder(
      context,
      Stack(
        children: <Widget>[
          SizedBox(
            width: (config.cellSize.width * widget.matrix.width()).toDouble(),
            height:
                (config.cellSize.height * widget.matrix.height()).toDouble(),
            child: Builder(builder: (ctx) {
              return CustomPaint(
                size: Size.infinite,
                painter: LinesPainter(
                  ctx,
                  config,
                  widget.matrix.normalize(),
                ),
              );
            }),
          ),
          widget.child,
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
