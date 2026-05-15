part of 'render.dart';

/// A leaf render object that lays out and paints a string. Wrapping is done
/// with [wrapText]; painting with [Painter.drawText].
class RenderText extends RenderBox {
  RenderText(
    this._text, {
    Color fg = Color.defaultFg,
    Color bg = Color.defaultBg,
    int style = 0,
    HorizontalAlign hAlign = HorizontalAlign.left,
    VerticalAlign vAlign = VerticalAlign.top,
    bool wrap = true,
  })  : _fg = fg,
        _bg = bg,
        _style = style,
        _hAlign = hAlign,
        _vAlign = vAlign,
        _wrap = wrap;

  String _text;
  String get text => _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    markNeedsLayout();
  }

  bool _wrap;
  bool get wrap => _wrap;
  set wrap(bool value) {
    if (value == _wrap) return;
    _wrap = value;
    markNeedsLayout();
  }

  Color _fg;
  Color get fg => _fg;
  set fg(Color value) {
    if (value == _fg) return;
    _fg = value;
    markNeedsPaint();
  }

  Color _bg;
  Color get bg => _bg;
  set bg(Color value) {
    if (value == _bg) return;
    _bg = value;
    markNeedsPaint();
  }

  int _style;
  int get style => _style;
  set style(int value) {
    if (value == _style) return;
    _style = value;
    markNeedsPaint();
  }

  HorizontalAlign _hAlign;
  HorizontalAlign get hAlign => _hAlign;
  set hAlign(HorizontalAlign value) {
    if (value == _hAlign) return;
    _hAlign = value;
    markNeedsPaint();
  }

  VerticalAlign _vAlign;
  VerticalAlign get vAlign => _vAlign;
  set vAlign(VerticalAlign value) {
    if (value == _vAlign) return;
    _vAlign = value;
    markNeedsPaint();
  }

  List<String> _layoutLines(int maxWidth) {
    if (_wrap && maxWidth < BoxConstraints.unbounded) {
      return wrapText(_text, maxWidth);
    }
    return _text.split('\n');
  }

  @override
  void performLayout() {
    var lines = _layoutLines(constraints.maxWidth);
    var longest = 0;
    for (var line in lines) {
      var len = line.runes.length;
      if (len > longest) longest = len;
    }
    size = constraints.constrain(CellSize(lines.length, longest));
  }

  @override
  int computeMaxIntrinsicWidth(int height) {
    var longest = 0;
    for (var line in _text.split('\n')) {
      var len = line.runes.length;
      if (len > longest) longest = len;
    }
    return longest;
  }

  @override
  int computeMinIntrinsicWidth(int height) {
    var longest = 0;
    for (var word in _text.split(RegExp(r'\s+'))) {
      var len = word.runes.length;
      if (len > longest) longest = len;
    }
    return longest;
  }

  @override
  int computeMinIntrinsicHeight(int width) => _heightAt(width);

  @override
  int computeMaxIntrinsicHeight(int width) => _heightAt(width);

  int _heightAt(int width) => _layoutLines(width).length;

  @override
  void paint(Painter painter) {
    painter.drawText(
      CellRect.fromOffsetSize(CellOffset.zero, size),
      _text,
      fg: _fg,
      bg: _bg,
      style: _style,
      hAlign: _hAlign,
      vAlign: _vAlign,
      wrap: _wrap,
    );
  }
}
