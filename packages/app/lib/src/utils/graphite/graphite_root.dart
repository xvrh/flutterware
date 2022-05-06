import 'package:flutter/widgets.dart';
import 'core/matrix.dart';
import 'graphite_edges.dart';
import 'graphite_grid.dart';

class GraphiteRoot extends StatefulWidget {
  final Matrix mtx;

  GraphiteRoot({
    required this.mtx,
  });
  @override
  _GraphiteRootState createState() => _GraphiteRootState();
}

class _GraphiteRootState extends State<GraphiteRoot> {
  @override
  Widget build(BuildContext context) {
    return GraphiteEdges(
      matrix: widget.mtx,
      child: GraphiteGrid(
        matrix: widget.mtx,
      ),
    );
  }
}
