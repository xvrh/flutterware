class PathTracker {
  final _root = _Level(null, 0);
  late var _current = _root;

  int split(int length) {
    assert(length >= 1);

    _current.ensureLength(length);

    for (var i = 0; i < length; i++) {
      var child = _current.children[i];
      if (child == null) {
        child = _Level(_current, i);
        _current.children[i] = child;
        _current = child;
        return i;
      } else if (!child.isCompleted) {
        _current = child;
        return i;
      }
    }
    throw StateError('Not found $length');
  }

  List<int> get id => _current.id;

  bool resetAndCheck() {
    _current.complete();
    _current = _root;
    return !_root.isCompleted;
  }
}

class _Level {
  final _Level? parent;
  final int index;
  List<_Level?>? _children;

  _Level(this.parent, this.index);

  void ensureLength(int length) {
    if (_children == null) {
      _children = List.filled(length, null);
    } else if (_children!.length != length) {
      throw StateError('${_children!.length} != $length');
    }
  }

  List<int> get id => [...?parent?.id, index];

  List<_Level?> get children => _children!;

  int get length => children.length;

  bool get isCompleted => children.every((e) => e != null && e.isCompleted);

  void complete() => ensureLength(0);
}
