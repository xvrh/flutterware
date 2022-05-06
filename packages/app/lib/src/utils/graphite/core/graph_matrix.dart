import 'dart:math';
import 'graph_basic.dart';
import 'matrix.dart';
import 'traverse_queue.dart';
import 'typings.dart';

class State {
  final Matrix mtx;
  TraverseQueue queue;
  int x;
  int y;
  State({
    required this.mtx,
    required this.queue,
    this.x = 0,
    this.y = 0,
  });
}

class GraphMatrix extends GraphBasic {
  GraphMatrix({required List<NodeInput> list}) : super(list: list);

  bool joinHasUnresolvedIncomes(NodeOutput item) {
    return item.passedIncomes.length != incomes(item.id).length;
  }

  void insertOrSkipNodeOnMatrix(
      NodeOutput item, State state, bool checkCollision) {
    var mtx = state.mtx;
    if (checkCollision && mtx.hasHorizontalCollision(state.x, state.y)) {
      mtx.insertRowBefore(state.y);
    }
    mtx.insert(state.x, state.y, item);
    markIncomesAsPassed(mtx, item);
    return;
  }

  int getLowestYAmongIncomes(NodeOutput item, Matrix mtx) {
    final incomes = item.passedIncomes;
    if (incomes.isEmpty) {
      return 0;
    }
    return incomes.map((String id) {
      var coords = mtx.find((NodeOutput itm) {
        return itm.id == id;
      });
      if (coords?.length != 2) {
        throw Exception('cannot find coordinates for passed income: $id');
      }
      return coords![1];
    }).reduce(min);
  }

  bool processOrSkipNodeOnMatrix(NodeOutput item, State state) {
    var mtx = state.mtx;
    var queue = state.queue;
    if (item.passedIncomes.isNotEmpty) {
      state.y = getLowestYAmongIncomes(item, mtx);
    }
    var hasLoops = this.hasLoops(item);
    var loopNodes = <LoopNode>[];
    if (hasLoops) {
      loopNodes = handleLoopEdges(item, state);
    }
    var needsLoopSkip = hasLoops && loopNodes.isEmpty;
    if (mtx.hasVerticalCollision(state.x, state.y) || needsLoopSkip) {
      queue.push(item);
      return false;
    }
    insertOrSkipNodeOnMatrix(item, state, false);
    if (loopNodes.isNotEmpty) {
      insertLoopEdges(item, state, loopNodes);
    }
    return true;
  }

  List<LoopNode> handleLoopEdges(NodeOutput item, State state) {
    var mtx = state.mtx;
    var loops = this.loops(item.id);
    if (loops.isEmpty) throw Exception('no loops found for node ${item.id}');
    var loopNodes = loops.map((String incomeId) {
      if (item.id == incomeId) {
        return LoopNode(
            id: incomeId, node: item, x: state.x, y: state.y, isSelfLoop: true);
      }
      var coords = mtx.find((NodeOutput n) {
        return n.id == incomeId;
      });
      if (coords?.length != 2) {
        throw Exception('loop target $incomeId not found on matrix');
      }
      var node = mtx.getByCoords(coords![0], coords[1]);
      if (node == null) {
        throw Exception('loop target node $incomeId not found on matrix');
      }
      return LoopNode(
          id: incomeId,
          node: node,
          x: coords[0],
          y: coords[1],
          isSelfLoop: false);
    }).toList();
    var skip = loopNodes.any((LoopNode income) {
      var checkY = income.y != 0 ? income.y - 1 : 0;
      return mtx.hasVerticalCollision(state.x, checkY);
    });
    return skip ? [] : loopNodes;
  }

  bool hasLoops(NodeOutput item) {
    return loops(item.id).isNotEmpty;
  }

  void insertLoopEdges(NodeOutput item, State state, List<LoopNode> loopNodes) {
    var mtx = state.mtx, initialX = state.x, initialY = state.y;
    for (var income in loopNodes) {
      var id = income.id, node = income.node, renderIncomeId = item.id;
      if (income.isSelfLoop) {
        state.x = initialX + 1;
        state.y = initialY;
        var selfLoopId = '$id-self';
        renderIncomeId = selfLoopId;
        insertOrSkipNodeOnMatrix(
            NodeOutput(
              id: selfLoopId,
              next: [id],
              anchorType: AnchorType.loop,
              anchorMargin: AnchorMargin.start,
              orientation: AnchorOrientation.bottomRight,
              from: item.id,
              to: id,
              isAnchor: true,
              renderIncomes: [node.id],
              passedIncomes: [item.id],
              childrenOnMatrix: 0,
            ),
            state,
            false);
      }
      var initialHeight = mtx.height();
      var fromId = '$id-${item.id}-from';
      var toId = '$id-${item.id}-to';
      node.renderIncomes.add(fromId);
      insertOrSkipNodeOnMatrix(
        NodeOutput(
          id: toId,
          next: [id],
          anchorMargin: AnchorMargin.start,
          anchorType: AnchorType.loop,
          orientation: AnchorOrientation.topRight,
          from: item.id,
          to: id,
          isAnchor: true,
          renderIncomes: [renderIncomeId],
          passedIncomes: [item.id],
          childrenOnMatrix: 0,
        ),
        state,
        true,
      );
      if (initialHeight != mtx.height()) {
        initialY++;
      }
      state.x = income.x;
      insertOrSkipNodeOnMatrix(
        NodeOutput(
          id: fromId,
          next: [id],
          anchorType: AnchorType.loop,
          anchorMargin: AnchorMargin.end,
          orientation: AnchorOrientation.topLeft,
          from: item.id,
          to: id,
          isAnchor: true,
          renderIncomes: [toId],
          passedIncomes: [item.id],
          childrenOnMatrix: 0,
        ),
        state,
        false,
      );
      state.x = initialX;
    }
    state.y = initialY;
    return;
  }

  void insertSplitOutcomes(
      NodeOutput item, State state, TraverseQueue levelQueue) {
    var queue = state.queue, outcomes = this.outcomes(item.id);
    if (outcomes.isEmpty) throw Exception('split ${item.id} has no outcomes');
    outcomes = List.from(outcomes);
    var firstOutcomeId = outcomes.removeAt(0);
    var first = node(firstOutcomeId);
    queue.add(incomeId: item.id, bufferQueue: levelQueue, items: [
      NodeInput(
        id: first.id,
        next: first.next,
      )
    ]);
    for (var outcomeId in outcomes) {
      state.y++;
      var id = '${item.id}-$outcomeId';
      insertOrSkipNodeOnMatrix(
        NodeOutput(
          id: id,
          next: [outcomeId],
          anchorType: AnchorType.split,
          anchorMargin: AnchorMargin.end,
          orientation: AnchorOrientation.bottomLeft,
          from: item.id,
          to: outcomeId,
          isAnchor: true,
          renderIncomes: [item.id],
          passedIncomes: [item.id],
          childrenOnMatrix: 0,
        ),
        state,
        true,
      );
      var v = node(outcomeId);
      queue.add(incomeId: id, bufferQueue: levelQueue, items: [v]);
    }
  }

  void insertJoinIncomes(NodeOutput item, State state, TraverseQueue levelQueue,
      bool addItemToQueue) {
    final mtx = state.mtx, queue = state.queue, incomes = item.passedIncomes;
    final lowestY = getLowestYAmongIncomes(item, mtx);
    for (var incomeId in incomes) {
      final found = mtx.findNode((NodeOutput n) {
        return n.id == incomeId;
      });
      if (found == null) throw Exception('income $incomeId was not found');
      final y = found.coords[1], income = found.item;
      if (lowestY == y) {
        item.renderIncomes.add(incomeId);
        income.childrenOnMatrix =
            min((income.childrenOnMatrix ?? 0) + 1, income.next.length);
        continue;
      }
      state.y = y;
      var id = '$incomeId-${item.id}';
      item.renderIncomes.add(id);
      insertOrSkipNodeOnMatrix(
        NodeOutput(
          id: id,
          next: [item.id],
          anchorType: AnchorType.join,
          anchorMargin: AnchorMargin.start,
          orientation: AnchorOrientation.bottomRight,
          from: incomeId,
          to: item.id,
          isAnchor: true,
          renderIncomes: [incomeId],
          passedIncomes: [incomeId],
          childrenOnMatrix: 1,
        ),
        state,
        false,
      );
    }
    if (addItemToQueue) {
      queue.add(
          incomeId: item.id,
          bufferQueue: levelQueue,
          items: getOutcomesArray(item.id));
    }
    return;
  }

  void markIncomesAsPassed(Matrix mtx, NodeOutput item) {
    for (var incomeId in item.renderIncomes) {
      var found = mtx.findNode((NodeOutput n) {
        return n.id == incomeId;
      });
      if (found == null) {
        throw Exception('income $incomeId not found on matrix');
      }
      var coords = found.coords, income = found.item;
      income.childrenOnMatrix =
          min((income.childrenOnMatrix ?? 0) + 1, income.next.length);
      mtx.insert(coords[0], coords[1], income);
    }
    return;
  }

  void resolveCurrentJoinIncomes(Matrix mtx, NodeOutput join) {
    markIncomesAsPassed(mtx, join);
    join.renderIncomes = [];
    return;
  }
}
