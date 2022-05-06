import 'typings.dart';

class TraverseQueue {
  TraverseQueue() : s = [];

  void add({
    String? incomeId,
    TraverseQueue? bufferQueue,
    required List<NodeInput> items,
  }) {
    for (var itm in items) {
      var item = find((NodeOutput el) {
        return el.id == itm.id;
      });
      if (item == null && bufferQueue != null) {
        item = bufferQueue.find((NodeOutput el) {
          return el.id == itm.id;
        });
      }
      if (item != null && incomeId != null) {
        item.passedIncomes.add(incomeId);
        return;
      }
      var incomes = incomeId == null ? <String>[] : <String>[incomeId];
      var renderIncomes = incomeId == null ? <String>[] : <String>[incomeId];
      s.add(NodeOutput(
        id: itm.id,
        next: itm.next,
        passedIncomes: incomes,
        renderIncomes: renderIncomes,
        childrenOnMatrix: 0,
        isAnchor: false,
      ));
    }
  }

  NodeOutput? find(bool Function(NodeOutput) f) {
    var idx = s.indexWhere(f);
    return idx != -1 ? s[idx] : null;
  }

  void push(NodeOutput item) {
    s.add(item);
  }

  int length() {
    return s.length;
  }

  bool some(bool Function(NodeOutput) f) {
    return s.any(f);
  }

  NodeOutput shift() {
    if (s.isEmpty) throw Exception('Queue is empty');
    return s.removeAt(0);
  }

  TraverseQueue drain() {
    var queue = TraverseQueue();
    queue.s.addAll(s);
    s = [];
    return queue;
  }

  List<NodeOutput> s;
}
