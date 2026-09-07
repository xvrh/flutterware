// How a paint stack is spelled in a file, and read back out of one.
//
// Its own organ because TWO grammars carry it: a scene file spells a text's
// own stack, and a token library spells the stack a shared style declares.
// One copy each is two dialects a month later.
//
// The vocabulary is the model's own class names, like the rest of the
// grammar — `StrokeLayer(width: 14, paint: SolidPaint(SceneColor(0xFF…)))` —
// because a spelling that differs from the type is a spelling the compiler
// cannot check. Every default is omitted, so the common layer is short.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutterware/scene_authoring.dart';

/// What a refusal needs: where it is, what was found, and what to do instead.
typedef Refuse = void Function(int offset, String construct, String message);

/// `[StrokeLayer(width: 14), FillLayer(paint: …)]`, back to front.
String emitSceneLayers(List<TextLayer> layers) =>
    '[${layers.map(_layer).join(', ')}]';

String _layer(TextLayer l) {
  var args = <String>[];
  if (l case StrokeLayer(:var width, :var join)) {
    args.add('width: ${_num(width)}');
    if (join != SceneStrokeJoin.round) {
      args.add('join: SceneStrokeJoin.${join.name}');
    }
  }
  if (l.paint case var p?) args.add('paint: ${_paint(p)}');
  if (l.blur != 0) args.add('blur: ${_num(l.blur)}');
  if (l.dx != 0) args.add('dx: ${_num(l.dx)}');
  if (l.dy != 0) args.add('dy: ${_num(l.dy)}');
  if (l.opacity != 1) args.add('opacity: ${_num(l.opacity)}');
  return '${l is StrokeLayer ? 'StrokeLayer' : 'FillLayer'}(${args.join(', ')})';
}

String _paint(ScenePaint p) => switch (p) {
  SolidPaint(:var color) => 'SolidPaint(${_color(color)})',
  LinearPaint(:var colors, :var stops, :var begin, :var end) => [
    'LinearPaint(colors: [${colors.map(_color).join(', ')}]',
    if (stops != null) ', stops: [${stops.map(_num).join(', ')}]',
    if (begin != SceneAlignment.topCenter) ', begin: ${_alignment(begin)}',
    if (end != SceneAlignment.bottomCenter) ', end: ${_alignment(end)}',
    ')',
  ].join(),
};

const _namedAlignments = {
  'topLeft': SceneAlignment.topLeft,
  'topCenter': SceneAlignment.topCenter,
  'topRight': SceneAlignment.topRight,
  'centerLeft': SceneAlignment.centerLeft,
  'center': SceneAlignment.center,
  'centerRight': SceneAlignment.centerRight,
  'bottomLeft': SceneAlignment.bottomLeft,
  'bottomCenter': SceneAlignment.bottomCenter,
  'bottomRight': SceneAlignment.bottomRight,
};

String _alignment(SceneAlignment a) {
  for (var e in _namedAlignments.entries) {
    if (e.value == a) return 'SceneAlignment.${e.key}';
  }
  return 'SceneAlignment(${_num(a.x)}, ${_num(a.y)})';
}

String _color(SceneColor c) =>
    'SceneColor(0x${c.argb.toRadixString(16).toUpperCase().padLeft(8, '0')})';

String _num(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

// ── reading ────────────────────────────────────────────────────────────────

/// The paint stack out of a `[…]` literal, or null when [e] is not one.
/// Refuses per element, so one bad layer does not lose the rest.
List<TextLayer>? readSceneLayers(Expression e, Refuse refuse) {
  if (e is! ListLiteral) {
    refuse(
      e.offset,
      'layers',
      'a paint stack is a list, back to front — '
          'layers: [StrokeLayer(width: 14), FillLayer()]',
    );
    return null;
  }
  var out = <TextLayer>[];
  for (var element in e.elements) {
    if (element is! Expression) {
      refuse(element.offset, 'layers', 'a stack lists its passes one by one');
      continue;
    }
    var layer = _readLayer(element, refuse);
    if (layer != null) out.add(layer);
  }
  return out;
}

TextLayer? _readLayer(Expression e, Refuse refuse) {
  var read = _call(e);
  if (read == null || (read.$1 != 'FillLayer' && read.$1 != 'StrokeLayer')) {
    refuse(
      e.offset,
      'layers',
      'a pass is FillLayer(…) or StrokeLayer(width: …) — nothing else is '
          'on the allowlist',
    );
    return null;
  }
  var (name, args) = read;
  var named = _named(args, 'a pass', refuse);
  if (named == null) return null;

  ScenePaint? paint;
  if (named.remove('paint') case var p?) {
    paint = _readPaint(p, refuse);
    if (paint == null) return null;
  }
  var blur = _take(named, 'blur', refuse) ?? 0;
  var dx = _take(named, 'dx', refuse) ?? 0;
  var dy = _take(named, 'dy', refuse) ?? 0;
  var opacity = _take(named, 'opacity', refuse) ?? 1;

  if (name == 'FillLayer') {
    if (!_rest(named, 'FillLayer', refuse)) return null;
    return FillLayer(
      paint: paint,
      blur: blur,
      dx: dx,
      dy: dy,
      opacity: opacity,
    );
  }
  var width = _take(named, 'width', refuse) ?? 1;
  var join = SceneStrokeJoin.round;
  if (named.remove('join') case var j?) {
    var read = _enumMember(
      j,
      'SceneStrokeJoin',
      SceneStrokeJoin.values.map((v) => v.name),
    );
    if (read == null) {
      refuse(
        j.offset,
        'layers',
        'a join is SceneStrokeJoin.miter, .round or .bevel',
      );
      return null;
    }
    join = SceneStrokeJoin.values.firstWhere((v) => v.name == read);
  }
  if (!_rest(named, 'StrokeLayer', refuse)) return null;
  return StrokeLayer(
    width: width,
    join: join,
    paint: paint,
    blur: blur,
    dx: dx,
    dy: dy,
    opacity: opacity,
  );
}

ScenePaint? _readPaint(Expression e, Refuse refuse) {
  var read = _call(e);
  switch (read) {
    case ('SolidPaint', var args) when args.arguments.length == 1:
      var color = _readColor(args.arguments.single.argumentExpression, refuse);
      return color == null ? null : SolidPaint(color);
    case ('LinearPaint', var args):
      var named = _named(args, 'a gradient', refuse);
      if (named == null) return null;
      var colorList = named.remove('colors');
      if (colorList is! ListLiteral) {
        refuse(
          e.offset,
          'paint',
          'a gradient names its colours — '
              'LinearPaint(colors: [SceneColor(0x…), SceneColor(0x…)])',
        );
        return null;
      }
      var colors = <SceneColor>[];
      for (var c in colorList.elements) {
        if (c is! Expression) continue;
        var color = _readColor(c, refuse);
        if (color == null) return null;
        colors.add(color);
      }
      List<double>? stops;
      if (named.remove('stops') case ListLiteral l) {
        stops = [
          for (var s in l.elements)
            if (s is Expression) ?_number(s),
        ];
      }
      var begin = _readAlignment(named.remove('begin'), refuse);
      var end = _readAlignment(named.remove('end'), refuse);
      if (!_rest(named, 'LinearPaint', refuse)) return null;
      return LinearPaint(
        colors: colors,
        stops: stops,
        begin: begin ?? SceneAlignment.topCenter,
        end: end ?? SceneAlignment.bottomCenter,
      );
    default:
      refuse(
        e.offset,
        'paint',
        'a paint is SolidPaint(SceneColor(0x…)) or '
            'LinearPaint(colors: […]) — nothing else is on the allowlist',
      );
      return null;
  }
}

SceneAlignment? _readAlignment(Expression? e, Refuse refuse) {
  if (e == null) return null;
  if (_enumMember(e, 'SceneAlignment', _namedAlignments.keys) case var name?) {
    return _namedAlignments[name];
  }
  if (_call(e) case ('SceneAlignment', var args)
      when args.arguments.length == 2) {
    var x = _number(args.arguments[0].argumentExpression);
    var y = _number(args.arguments[1].argumentExpression);
    if (x != null && y != null) return SceneAlignment(x, y);
  }
  refuse(
    e.offset,
    'paint',
    'an end of a gradient is SceneAlignment.topCenter or '
        'SceneAlignment(0, -1)',
  );
  return null;
}

SceneColor? _readColor(Expression e, Refuse refuse) {
  if (_call(e) case ('SceneColor', var args) when args.arguments.length == 1) {
    var v = args.arguments.single;
    if (v is IntegerLiteral && v.value != null) return SceneColor(v.value!);
  }
  refuse(e.offset, 'paint', 'expected a color, spelled SceneColor(0xAARRGGBB)');
  return null;
}

/// A constructor call, `const` or not, as a name and its arguments.
(String, ArgumentList)? _call(Expression e) => switch (e) {
  InstanceCreationExpression(:var constructorName, :var argumentList) => (
    constructorName.type.name.lexeme,
    argumentList,
  ),
  MethodInvocation(:var methodName, target: null, :var argumentList) => (
    methodName.name,
    argumentList,
  ),
  _ => null,
};

String? _enumMember(Expression e, String prefix, Iterable<String> names) =>
    e is PrefixedIdentifier &&
        e.prefix.name == prefix &&
        names.contains(e.identifier.name)
    ? e.identifier.name
    : null;

Map<String, Expression>? _named(ArgumentList args, String what, Refuse refuse) {
  var named = <String, Expression>{};
  for (var arg in args.arguments) {
    if (arg is NamedArgument) {
      named[arg.name.lexeme] = arg.argumentExpression;
    } else {
      refuse(arg.offset, 'layers', '$what names each of its values');
      return null;
    }
  }
  return named;
}

double? _take(Map<String, Expression> named, String key, Refuse refuse) {
  var e = named.remove(key);
  if (e == null) return null;
  var v = _number(e);
  if (v == null) refuse(e.offset, 'layers', '$key is a number');
  return v;
}

double? _number(Expression e) => switch (e) {
  IntegerLiteral(:var value?) => value.toDouble(),
  DoubleLiteral(:var value) => value,
  PrefixExpression(operator: var op, operand: var inner)
      when op.lexeme == '-' =>
    switch (_number(inner)) {
      var v? => -v,
      null => null,
    },
  _ => null,
};

bool _rest(Map<String, Expression> named, String what, Refuse refuse) {
  for (var e in named.entries) {
    refuse(e.value.offset, 'layers', '$what has no "${e.key}"');
  }
  return named.isEmpty;
}
