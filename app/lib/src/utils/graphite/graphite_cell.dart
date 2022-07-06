import 'package:flutter/widgets.dart';
import 'core/typings.dart';

typedef NodeCellBuilder = Widget Function(
    BuildContext context, MatrixNode node);

Widget _defaultNodeCellBuilder(BuildContext context, MatrixNode node) {
  return Container(
    alignment: Alignment.center,
    color: Color(0xFF26A69A),
    child: Text(node.id),
  );
}

class GraphiteCell extends StatefulWidget {
  final MatrixNode node;
  final double cellPadding;

  final NodeCellBuilder? builder;

  const GraphiteCell({
    required this.node,
    required this.cellPadding,
    this.builder,
    super.key,
  });
  @override
  State<GraphiteCell> createState() => _GraphiteCellState();
}

class _GraphiteCellState extends State<GraphiteCell> {
  @override
  Widget build(BuildContext context) {
    var node = widget.node;
    return node.isAnchor
        ? IgnorePointer(child: Container())
        : Builder(builder: (ctx) {
            return widget.builder == null
                ? _defaultNodeCellBuilder(ctx, node)
                : widget.builder!(ctx, node);
          });
  }
}

class GraphiteAnchor extends StatefulWidget {
  const GraphiteAnchor({
    super.key,
  });

  @override
  State<GraphiteAnchor> createState() => _GraphiteAnchorState();
}

class _GraphiteAnchorState extends State<GraphiteAnchor> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(),
    );
  }
}
