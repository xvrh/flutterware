enum NodeType {
  unknown,
  rootSimple,
  rootSplit,
  simple,
  split,
  join,
  splitJoin,
}

enum AnchorOrientation {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

enum AnchorMargin { none, start, end }

class NodeInput {
  NodeInput({
    required this.id,
    required this.next,
  });

  final String id;
  final List<String> next;
}

enum AnchorType {
  unknown,
  join,
  split,
  loop,
}

class MatrixNode extends NodeOutput {
  MatrixNode({
    required this.x,
    required this.y,
    required super.id,
    required super.next,
    super.anchorType,
    super.from,
    super.to,
    super.orientation,
    super.isAnchor,
    super.anchorMargin,
    super.passedIncomes,
    super.renderIncomes,
    super.childrenOnMatrix,
  });
  static MatrixNode fromNodeOutput(
      {required int x, required int y, required NodeOutput nodeOutput}) {
    return MatrixNode(
      x: x,
      y: y,
      id: nodeOutput.id,
      next: nodeOutput.next,
      anchorType: nodeOutput.anchorType,
      from: nodeOutput.from,
      to: nodeOutput.to,
      orientation: nodeOutput.orientation,
      isAnchor: nodeOutput.isAnchor,
      anchorMargin: nodeOutput.anchorMargin,
      passedIncomes: nodeOutput.passedIncomes,
      renderIncomes: nodeOutput.renderIncomes,
      childrenOnMatrix: nodeOutput.childrenOnMatrix,
    );
  }

  final int x;
  final int y;
}

class NodeOutput extends NodeInput {
  NodeOutput({
    required super.id,
    required super.next,
    this.anchorType,
    this.from,
    this.to,
    this.orientation,
    this.isAnchor = false,
    this.passedIncomes = const [],
    this.renderIncomes = const [],
    this.childrenOnMatrix,
    this.anchorMargin,
  });

  final AnchorType? anchorType;
  final String? from;
  final String? to;
  final AnchorOrientation? orientation;
  final AnchorMargin? anchorMargin;

  final bool isAnchor;
  final List<String> passedIncomes;
  List<String> renderIncomes;
  int? childrenOnMatrix;
}

class LoopNode {
  LoopNode({
    required this.id,
    required this.node,
    required this.x,
    required this.y,
    this.isSelfLoop = false,
  });

  final String id;
  final NodeOutput node;
  final int x;
  final int y;
  final bool isSelfLoop;
}
