import 'typings.dart';

class FindNodeResult {
  FindNodeResult({
    required this.coords,
    required this.item,
  });
  List<int> coords;
  NodeOutput item;
}

enum MatrixOrientation {
  horizontal,
  vertical,
}

String fillWithSpaces(String str, int l) {
  while (str.length < l) {
    str += ' ';
  }
  return str;
}

class Matrix {
  Matrix()
      : s = [],
        orientation = MatrixOrientation.horizontal;

  int width() {
    return s.fold(0, (w, row) => row.length > w ? row.length : w);
  }

  int height() {
    return s.length;
  }

  bool hasHorizontalCollision(int x, int y) {
    if (s.isEmpty || y >= s.length) {
      return false;
    }
    var row = s[y];
    return row.any((NodeOutput? point) {
      if (point != null && !isAllChildrenOnMatrix(point)) {
        return true;
      }
      return false;
    });
  }

  bool hasVerticalCollision(int x, int y) {
    if (x >= width()) {
      return false;
    }
    return s.asMap().entries.any((data) {
      var index = data.key;
      var row = data.value;
      return index >= y && x < row.length && row[x] != null;
    });
  }

  int getFreeRowForColumn(int x) {
    if (height() == 0) {
      return 0;
    }
    final entries = s.asMap().entries.toList();
    final idx = entries.indexWhere((data) {
      var row = data.value;
      return row.isEmpty || x >= row.length || row[x] == null;
    });
    var y = idx == -1 ? height() : entries[idx].key;
    return y;
  }

  void extendHeight(int toValue) {
    while (height() < toValue) {
      s.add(List.filled(width(), null, growable: true));
    }
  }

  void extendWidth(int toValue) {
    for (var i = 0; i < height(); i++) {
      while (s[i].length < toValue) {
        s[i].add(null);
      }
    }
  }

  void insertRowBefore(int y) {
    var row = List<NodeOutput?>.filled(width(), null, growable: true);
    s.insert(y, row);
  }

  void insertColumnBefore(int x) {
    for (var row in s) {
      row.insert(x, null);
    }
  }

  List<int>? find(bool Function(NodeOutput) f) {
    List<int>? result;
    s.asMap().entries.any((rowEntry) {
      var y = rowEntry.key;
      var row = rowEntry.value;
      return row.asMap().entries.any((columnEntry) {
        var x = columnEntry.key;
        var cell = columnEntry.value;
        if (cell == null) return false;
        if (f(cell)) {
          result = [x, y];
          return true;
        }
        return false;
      });
    });
    return result;
  }

  FindNodeResult? findNode(bool Function(NodeOutput) f) {
    FindNodeResult? result;
    s.asMap().entries.any((rowEntry) {
      var y = rowEntry.key;
      var row = rowEntry.value;
      return row.asMap().entries.any((columnEntry) {
        var x = columnEntry.key;
        var cell = columnEntry.value;
        if (cell == null) return false;
        if (f(cell)) {
          result = FindNodeResult(coords: [x, y], item: cell);
          return true;
        }
        return false;
      });
    });
    return result;
  }

  NodeOutput? getByCoords(int x, int y) {
    if (x >= width() || y >= height()) {
      return null;
    }
    return s[y][x];
  }

  void insert(int x, int y, NodeOutput? item) {
    if (height() <= y) {
      extendHeight(y + 1);
    }
    if (width() <= x) {
      extendWidth(x + 1);
    }
    s[y][x] = item;
  }

  bool isAllChildrenOnMatrix(NodeOutput item) {
    return item.next.length == item.childrenOnMatrix;
  }

  Map<String, MatrixNode> normalize() {
    var acc = <String, MatrixNode>{};
    s.asMap().entries.forEach((rowEntry) {
      var y = rowEntry.key;
      var row = rowEntry.value;
      row.asMap().entries.forEach((columnEntry) {
        var x = columnEntry.key;
        var item = columnEntry.value;
        if (item != null) {
          acc[item.id] =
              MatrixNode.fromNodeOutput(x: x, y: y, nodeOutput: item);
        }
      });
    });
    return acc;
  }

  Matrix rotate() {
    var newMtx = Matrix();
    s.asMap().forEach((y, row) {
      row.asMap().forEach((x, cell) {
        newMtx.insert(y, x, cell);
      });
    });
    newMtx.orientation = orientation == MatrixOrientation.horizontal
        ? MatrixOrientation.vertical
        : MatrixOrientation.horizontal;
    return newMtx;
  }

  @override
  String toString() {
    var result = '', max = 0;
    for (var row in s) {
      for (var cell in row) {
        if (cell == null) continue;
        if (cell.id.length > max) {
          max = cell.id.length;
        }
      }
    }
    for (var row in s) {
      for (var cell in row) {
        if (cell == null) {
          result += fillWithSpaces(' ', max);
          result += '│';
          continue;
        }
        result += fillWithSpaces(cell.id, max);
        result += '│';
      }
      result += '\n';
    }
    return result;
  }

  MatrixOrientation orientation;
  List<List<NodeOutput?>> s;
}
