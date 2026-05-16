part of 'render.dart';

/// The layout axis of a [RenderFlex].
enum Axis { horizontal, vertical }

/// How children are placed along the main axis when there is free space.
enum MainAxisAlignment {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// How children are placed along the cross axis.
enum CrossAxisAlignment { start, end, center, stretch }

/// Whether a [RenderFlex] is as large as possible or as small as its children
/// along the main axis.
enum MainAxisSize { min, max }

/// How a flexible child fills the main-axis space allotted to it.
enum FlexFit { tight, loose }

/// [ParentData] for [RenderFlex] children: adds a flex factor and fit.
class FlexParentData extends BoxParentData {
  int flex = 0;
  FlexFit fit = FlexFit.loose;
}

/// A multi-child render object that lays children out along one axis — the
/// shared mechanism behind `Row` and `Column`.
class RenderFlex extends RenderBox {
  RenderFlex({
    required Axis direction,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
    MainAxisSize mainAxisSize = MainAxisSize.max,
    List<RenderBox> children = const [],
  })  : _direction = direction,
        _mainAxisAlignment = mainAxisAlignment,
        _crossAxisAlignment = crossAxisAlignment,
        _mainAxisSize = mainAxisSize {
    addAll(children);
  }

  Axis _direction;
  Axis get direction => _direction;
  set direction(Axis value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  MainAxisAlignment _mainAxisAlignment;
  MainAxisAlignment get mainAxisAlignment => _mainAxisAlignment;
  set mainAxisAlignment(MainAxisAlignment value) {
    if (value == _mainAxisAlignment) return;
    _mainAxisAlignment = value;
    markNeedsLayout();
  }

  CrossAxisAlignment _crossAxisAlignment;
  CrossAxisAlignment get crossAxisAlignment => _crossAxisAlignment;
  set crossAxisAlignment(CrossAxisAlignment value) {
    if (value == _crossAxisAlignment) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  MainAxisSize _mainAxisSize;
  MainAxisSize get mainAxisSize => _mainAxisSize;
  set mainAxisSize(MainAxisSize value) {
    if (value == _mainAxisSize) return;
    _mainAxisSize = value;
    markNeedsLayout();
  }

  final List<RenderBox> _children = [];

  /// The children, in layout order. Read-only; mutate via [add]/[remove].
  List<RenderBox> get children => List.unmodifiable(_children);

  void add(RenderBox child) {
    _children.add(child);
    adoptChild(child);
  }

  void addAll(List<RenderBox> children) {
    for (var child in children) {
      add(child);
    }
  }

  void remove(RenderBox child) {
    _children.remove(child);
    dropChild(child);
  }

  void clearChildren() {
    var copy = _children.toList();
    _children.clear();
    for (var child in copy) {
      dropChild(child);
    }
  }

  /// Inserts [child], placing it immediately after [after] (or first when
  /// [after] is null). Adopts the child.
  void insert(RenderBox child, {RenderBox? after}) {
    _insertIntoList(child, after);
    adoptChild(child);
  }

  /// Relocates an already-adopted [child] to immediately after [after] (or
  /// first when [after] is null). Does not re-adopt.
  void move(RenderBox child, {RenderBox? after}) {
    assert(_children.contains(child), 'move() child must already be present.');
    _children.remove(child);
    _insertIntoList(child, after);
    markNeedsLayout();
  }

  void _insertIntoList(RenderBox child, RenderBox? after) {
    if (after == null) {
      _children.insert(0, child);
    } else {
      var index = _children.indexOf(after);
      assert(index != -1, '`after` is not a child of this RenderFlex.');
      _children.insert(index + 1, child);
    }
  }

  /// Sets the flex factor and fit of an already-added [child].
  void setFlex(RenderBox child, int flex, {FlexFit fit = FlexFit.loose}) {
    var pd = child.parentData! as FlexParentData;
    pd.flex = flex;
    pd.fit = fit;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! FlexParentData) {
      child.parentData = FlexParentData();
    }
  }

  @override
  void redepthChildren() {
    for (var child in _children) {
      redepthChild(child);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visitor) {
    for (var child in _children) {
      visitor(child);
    }
  }

  bool get _isHorizontal => direction == Axis.horizontal;

  int _mainOf(CellSize s) => _isHorizontal ? s.cols : s.rows;
  int _crossOf(CellSize s) => _isHorizontal ? s.rows : s.cols;

  CellSize _sizeFor(int main, int cross) =>
      _isHorizontal ? CellSize(cross, main) : CellSize(main, cross);

  CellOffset _offsetFor(int main, int cross) =>
      _isHorizontal ? CellOffset(cross, main) : CellOffset(main, cross);

  /// Distributes [total] across the slots proportional to [weights]; the
  /// rounding remainder is spread across the slots by a cumulative-floor
  /// (Bresenham) split, so the parts always sum to exactly [total].
  static List<int> _splitProportional(int total, List<int> weights) {
    var sum = weights.fold<int>(0, (a, b) => a + b);
    if (sum <= 0 || total <= 0) {
      return List<int>.filled(weights.length, 0);
    }
    var result = <int>[];
    var allocated = 0;
    var acc = 0;
    for (var w in weights) {
      acc += total * w;
      var upTo = acc ~/ sum;
      result.add(upTo - allocated);
      allocated = upTo;
    }
    return result;
  }

  /// The weight of each of the [n]+1 gap slots (before child 0, between each
  /// pair, after child n-1) for a main-axis alignment.
  static List<int> _gapWeights(MainAxisAlignment alignment, int n) {
    var w = List<int>.filled(n + 1, 0);
    switch (alignment) {
      case MainAxisAlignment.start:
        w[n] = 1;
      case MainAxisAlignment.end:
        w[0] = 1;
      case MainAxisAlignment.center:
        w[0] = 1;
        w[n] = 1;
      case MainAxisAlignment.spaceBetween:
        for (var i = 1; i < n; i++) {
          w[i] = 1;
        }
      case MainAxisAlignment.spaceAround:
        for (var i = 1; i < n; i++) {
          w[i] = 2;
        }
        w[0] = 1;
        w[n] = 1;
      case MainAxisAlignment.spaceEvenly:
        for (var i = 0; i <= n; i++) {
          w[i] = 1;
        }
    }
    return w;
  }

  BoxConstraints _childConstraints(
      int maxCross, bool stretch, int minMain, int maxMain) {
    if (_isHorizontal) {
      return BoxConstraints(
        minWidth: minMain,
        maxWidth: maxMain,
        minHeight: stretch ? maxCross : 0,
        maxHeight: maxCross,
      );
    }
    return BoxConstraints(
      minWidth: stretch ? maxCross : 0,
      maxWidth: maxCross,
      minHeight: minMain,
      maxHeight: maxMain,
    );
  }

  @override
  void performLayout() {
    var maxMain = _isHorizontal ? constraints.maxWidth : constraints.maxHeight;
    var maxCross = _isHorizontal ? constraints.maxHeight : constraints.maxWidth;
    var canStretch = crossAxisAlignment == CrossAxisAlignment.stretch &&
        maxCross < BoxConstraints.unbounded;

    // Pass 1: inflexible children.
    var allocatedMain = 0;
    var crossExtent = 0;
    var flexFactors = <int>[];
    for (var child in _children) {
      var pd = child.parentData! as FlexParentData;
      if (pd.flex > 0) {
        flexFactors.add(pd.flex);
        continue;
      }
      child.layout(
        _childConstraints(maxCross, canStretch, 0, BoxConstraints.unbounded),
        parentUsesSize: true,
      );
      allocatedMain += _mainOf(child.size);
      var cross = _crossOf(child.size);
      if (cross > crossExtent) crossExtent = cross;
    }

    // Pass 2: flexible children share the free main-axis space.
    var freeMain = maxMain >= BoxConstraints.unbounded
        ? 0
        : (maxMain - allocatedMain < 0 ? 0 : maxMain - allocatedMain);
    var shares = _splitProportional(freeMain, flexFactors);
    var shareIndex = 0;
    var flexMain = 0;
    for (var child in _children) {
      var pd = child.parentData! as FlexParentData;
      if (pd.flex <= 0) continue;
      var extent = shares[shareIndex++];
      var minMain = pd.fit == FlexFit.tight ? extent : 0;
      child.layout(
        _childConstraints(maxCross, canStretch, minMain, extent),
        parentUsesSize: true,
      );
      flexMain += _mainOf(child.size);
      var cross = _crossOf(child.size);
      if (cross > crossExtent) crossExtent = cross;
    }

    // Own size.
    var contentMain = allocatedMain + flexMain;
    int mainExtent;
    if (mainAxisSize == MainAxisSize.max &&
        maxMain < BoxConstraints.unbounded) {
      mainExtent = maxMain;
    } else {
      mainExtent = contentMain;
    }
    size = constraints.constrain(_sizeFor(mainExtent, crossExtent));
    var resolvedMain = _mainOf(size);
    var resolvedCross = _crossOf(size);

    // Position children: distribute the leftover main space into gap slots.
    var leftover = resolvedMain - contentMain;
    if (leftover < 0) leftover = 0;
    var gaps = _splitProportional(
      leftover,
      _gapWeights(mainAxisAlignment, _children.length),
    );
    var cursor = gaps[0];
    for (var i = 0; i < _children.length; i++) {
      var child = _children[i];
      var childCross = _crossOf(child.size);
      var crossPos = switch (crossAxisAlignment) {
        CrossAxisAlignment.start => 0,
        CrossAxisAlignment.end => resolvedCross - childCross,
        CrossAxisAlignment.center => (resolvedCross - childCross) ~/ 2,
        CrossAxisAlignment.stretch => 0,
      };
      (child.parentData! as FlexParentData).offset =
          _offsetFor(cursor, crossPos);
      cursor += _mainOf(child.size) + gaps[i + 1];
    }
  }

  int _intrinsicMain(bool useMax, int crossLimit) {
    var inflexibleSum = 0;
    var maxFlexFraction = 0;
    var totalFlex = 0;
    for (var child in _children) {
      var flex = (child.parentData! as FlexParentData).flex;
      var extent = _isHorizontal
          ? (useMax
              ? child.getMaxIntrinsicWidth(crossLimit)
              : child.getMinIntrinsicWidth(crossLimit))
          : (useMax
              ? child.getMaxIntrinsicHeight(crossLimit)
              : child.getMinIntrinsicHeight(crossLimit));
      if (flex > 0) {
        totalFlex += flex;
        var fraction = (extent + flex - 1) ~/ flex; // ceil(extent / flex)
        if (fraction > maxFlexFraction) maxFlexFraction = fraction;
      } else {
        inflexibleSum += extent;
      }
    }
    return inflexibleSum + maxFlexFraction * totalFlex;
  }

  int _intrinsicCross(bool useMax, int mainLimit) {
    var result = 0;
    for (var child in _children) {
      var extent = _isHorizontal
          ? (useMax
              ? child.getMaxIntrinsicHeight(mainLimit)
              : child.getMinIntrinsicHeight(mainLimit))
          : (useMax
              ? child.getMaxIntrinsicWidth(mainLimit)
              : child.getMinIntrinsicWidth(mainLimit));
      if (extent > result) result = extent;
    }
    return result;
  }

  @override
  int computeMinIntrinsicWidth(int height) => _isHorizontal
      ? _intrinsicMain(false, height)
      : _intrinsicCross(false, height);

  @override
  int computeMaxIntrinsicWidth(int height) => _isHorizontal
      ? _intrinsicMain(true, height)
      : _intrinsicCross(true, height);

  @override
  int computeMinIntrinsicHeight(int width) => _isHorizontal
      ? _intrinsicCross(false, width)
      : _intrinsicMain(false, width);

  @override
  int computeMaxIntrinsicHeight(int width) => _isHorizontal
      ? _intrinsicCross(true, width)
      : _intrinsicMain(true, width);

  @override
  void paint(Painter painter) {
    for (var child in _children) {
      var offset = (child.parentData! as FlexParentData).offset;
      child.paint(painter.translate(offset));
    }
  }
}
