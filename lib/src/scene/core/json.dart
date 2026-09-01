// The model as data, both ways.
//
// Two shapes, deliberately different. The WIRE (`SceneDocument.toWire`) is a
// picture: rendered values, fx folded in, selection along for the ride — what
// the editor pushes at a live guest sixty times a second. This file is the
// other one: the AUTHORED document, exactly what the file says, which is what
// a guest needs when it is going to evaluate the motion itself rather than be
// fed frames — an export walking a playhead in a tester, or an app mounting a
// scene it was handed.
import 'model.dart';
import 'motion_model.dart';
import 'values.dart';

/// A whole file as data: the scene, the class it is named after, and the
/// motions that animate it.
Map<String, Object?> sceneFileToJson(
  SceneDocument doc, {
  required String className,
  Map<String, MotionDocument> motions = const {},
}) => {
  'class': className,
  'scene': doc.toJson(),
  'motions': {for (var e in motions.entries) e.key: e.value.toJson()},
};

/// The inverse of [sceneFileToJson].
({String className, SceneDocument scene, Map<String, MotionDocument> motions})
sceneFileFromJson(Map<String, Object?> json) {
  var className = json['class']! as String;
  var scene = sceneFromJson((json['scene']! as Map).cast<String, Object?>());
  return (
    className: className,
    scene: scene,
    motions: {
      for (var e in ((json['motions'] as Map?) ?? const {}).entries)
        '${e.key}': motionFromJson(
          (e.value as Map).cast<String, Object?>(),
          sceneClassName: className,
        ),
    },
  );
}

extension SceneDocumentJson on SceneDocument {
  /// The authored plane, complete: parameters, nodes, and which properties
  /// read which parameter. Never the fx plane, which belongs to its writers.
  Map<String, Object?> toJson() => {
    'params': [
      for (var p in params)
        {
          'name': p.name,
          'kind': p.kind.name,
          'default': _valueToJson(p.defaultValue),
        },
    ],
    'root': _nodeToJson(root),
  };
}

SceneDocument sceneFromJson(Map<String, Object?> json) {
  var root = _nodeFromJson((json['root']! as Map).cast<String, Object?>());
  var doc = SceneDocument(root as FrameNode);
  for (var raw in (json['params'] as List? ?? const [])) {
    var p = (raw as Map).cast<String, Object?>();
    var kind = SceneParamKind.values.byName(p['kind']! as String);
    doc.params.add(
      SceneParamDecl(
        p['name']! as String,
        kind,
        _paramValue(kind, p['default']),
      ),
    );
  }
  return doc;
}

Map<String, Object?> _nodeToJson(SceneNode n) => {
  'name': n.name,
  'kind': n.typeName,
  if (n.x != 0) 'x': n.x,
  if (n.y != 0) 'y': n.y,
  if (n.width != null) 'w': n.width,
  if (n.height != null) 'h': n.height,
  if (n.fill != null) 'fill': n.fill!.argb,
  if (n.cornerRadius != 0) 'corner': n.cornerRadius,
  if (n.opacity != 1) 'opacity': n.opacity,
  if (n.paramRefs.isNotEmpty) 'paramRefs': {...n.paramRefs},
  ...switch (n) {
    FrameNode f => {
      'layout': f.layout.name,
      'gap': f.gap,
      'padding': f.padding,
      'mainAlign': f.mainAlign.name,
      'crossAlign': f.crossAlign.name,
      'children': [for (var c in f.children) _nodeToJson(c)],
    },
    TextNode t => {
      'text': t.text,
      'fontSize': t.fontSize,
      'weight': t.weight.index,
      'color': t.color.argb,
    },
    ShapeNode s => {'circle': s.circle},
    ExternalNode e => {
      'entry': e.entry,
      'args': {...e.args},
    },
  },
};

SceneNode _nodeFromJson(Map<String, Object?> json) {
  var name = json['name']! as String;
  double? number(String key) => (json[key] as num?)?.toDouble();
  var node = switch (json['kind']) {
    'Frame' =>
      FrameNode(
          name,
          layout: NodeLayout.values.byName(json['layout']! as String),
        )
        ..gap = number('gap') ?? 8
        ..padding = number('padding') ?? 0
        ..mainAlign = SceneMainAxisAlignment.values.byName(
          json['mainAlign'] as String? ?? 'start',
        )
        ..crossAlign = SceneCrossAxisAlignment.values.byName(
          json['crossAlign'] as String? ?? 'center',
        )
        ..children.addAll([
          for (var c in (json['children'] as List? ?? const []))
            _nodeFromJson((c as Map).cast<String, Object?>()),
        ]),
    'Text' =>
      TextNode(name, json['text']! as String)
        ..fontSize = number('fontSize') ?? 16
        ..weight =
            SceneFontWeight.values[(json['weight'] as num?)?.toInt() ?? 3]
        ..color = SceneColor((json['color'] as num?)?.toInt() ?? 0xFF1A1A1A),
    'Shape' => ShapeNode(name, circle: json['circle'] == true),
    'Ext' => ExternalNode(
      name,
      json['entry']! as String,
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    _ => throw ArgumentError('unknown node kind "${json['kind']}"'),
  };
  return node
    ..x = number('x') ?? 0
    ..y = number('y') ?? 0
    ..width = number('w')
    ..height = number('h')
    ..fill = json['fill'] == null
        ? null
        : SceneColor((json['fill']! as num).toInt())
    ..cornerRadius = number('corner') ?? 0
    ..opacity = number('opacity') ?? 1
    ..paramRefs.addAll(
      ((json['paramRefs'] as Map?) ?? const {}).map(
        (k, v) => MapEntry('$k', '$v'),
      ),
    );
}

extension MotionDocumentJson on MotionDocument {
  Map<String, Object?> toJson() => {
    'params': [
      for (var p in params)
        {
          'name': p.name,
          'kind': p.kind.name,
          'default': _valueToJson(p.defaultValue),
        },
    ],
    'groups': [
      for (var g in groups)
        {
          'name': g.name,
          'target': g.target,
          'tracks': {
            for (var e in g.tracks.entries) e.key: _trackToJson(e.value),
          },
          'args': {for (var e in g.args.entries) e.key: _trackToJson(e.value)},
        },
    ],
    'timeline': _exprToJson(timeline),
  };
}

MotionDocument motionFromJson(
  Map<String, Object?> json, {
  required String sceneClassName,
}) {
  var doc = MotionDocument(sceneClassName: sceneClassName);
  for (var raw in (json['params'] as List? ?? const [])) {
    var p = (raw as Map).cast<String, Object?>();
    var kind = SceneParamKind.values.byName(p['kind']! as String);
    doc.params.add(
      SceneParamDecl(
        p['name']! as String,
        kind,
        _paramValue(kind, p['default']),
      ),
    );
  }
  for (var raw in (json['groups'] as List? ?? const [])) {
    var g = (raw as Map).cast<String, Object?>();
    var group = AnimateGroup(g['name']! as String, g['target']! as String);
    for (var e in ((g['tracks'] as Map?) ?? const {}).entries) {
      group.tracks['${e.key}'] = _trackFromJson(
        (e.value as Map).cast<String, Object?>(),
      );
    }
    for (var e in ((g['args'] as Map?) ?? const {}).entries) {
      group.args['${e.key}'] = _trackFromJson(
        (e.value as Map).cast<String, Object?>(),
      );
    }
    doc.groups.add(group);
  }
  doc.timeline = _exprFromJson(
    (json['timeline']! as Map).cast<String, Object?>(),
  );
  return doc;
}

Map<String, Object?> _trackToJson(MotionTrack t) => {
  'kind': t.kind.name,
  'keys': [
    for (var k in t.keys)
      {
        'at': k.at.inMicroseconds,
        'value': _valueToJson(k.value),
        if (k.curve != null) 'curve': k.curve,
        if (k.paramRef != null) 'paramRef': k.paramRef,
      },
  ],
};

MotionTrack _trackFromJson(Map<String, Object?> json) {
  var kind = TrackKind.values.byName(json['kind']! as String);
  return MotionTrack(kind, [
    for (var raw in (json['keys'] as List? ?? const []))
      if ((raw as Map).cast<String, Object?>() case var k)
        MotionKey(
          at: Duration(microseconds: (k['at']! as num).toInt()),
          value: kind == TrackKind.color
              ? SceneColor((k['value']! as num).toInt())
              : (k['value']! as num).toDouble(),
          curve: k['curve'] as String?,
          paramRef: k['paramRef'] as String?,
        ),
  ]);
}

Map<String, Object?> _exprToJson(TimelineExpr e) => switch (e) {
  GroupRef r => {'op': 'ref', 'name': r.name},
  ParExpr p => {
    'op': 'par',
    'children': [for (var c in p.children) _exprToJson(c)],
  },
  SeqExpr s => {
    'op': 'seq',
    'children': [for (var c in s.children) _exprToJson(c)],
  },
  AtExpr a => {
    'op': 'at',
    'offset': a.offset.inMicroseconds,
    'child': _exprToJson(a.child),
  },
  SpeedExpr s => {
    'op': 'speed',
    'factor': s.factor,
    'child': _exprToJson(s.child),
  },
  RepeatExpr r => {
    'op': 'repeat',
    'times': r.times,
    'child': _exprToJson(r.child),
  },
};

TimelineExpr _exprFromJson(Map<String, Object?> json) {
  List<TimelineExpr> children() => [
    for (var c in (json['children'] as List? ?? const []))
      _exprFromJson((c as Map).cast<String, Object?>()),
  ];
  TimelineExpr child() =>
      _exprFromJson((json['child']! as Map).cast<String, Object?>());
  return switch (json['op']) {
    'ref' => GroupRef(json['name']! as String),
    'par' => ParExpr(children()),
    'seq' => SeqExpr(children()),
    'at' => AtExpr(
      Duration(microseconds: (json['offset']! as num).toInt()),
      child(),
    ),
    'speed' => SpeedExpr((json['factor']! as num).toDouble(), child()),
    'repeat' => RepeatExpr((json['times']! as num).toInt(), child()),
    _ => throw ArgumentError('unknown timeline op "${json['op']}"'),
  };
}

Object? _valueToJson(Object? value) => switch (value) {
  SceneColor c => c.argb,
  _ => value,
};

/// A parameter's default, read back as the kind it was declared with — an
/// int in the file is a colour or a number depending on the hole it fills.
Object _paramValue(SceneParamKind kind, Object? raw) => switch (kind) {
  SceneParamKind.color => SceneColor((raw! as num).toInt()),
  SceneParamKind.number => (raw! as num).toDouble(),
  SceneParamKind.string => raw! as String,
};

/// Read back what [SceneDocument.toWire] wrote — a PICTURE, not a document.
///
/// The wire's values are already composed (base folded with every fx writer),
/// so they land in the authored slots here and draw exactly as sent. The one
/// exception is the imposed transform block, which has no authored slot at
/// all: it comes back as an fx contribution, which is where a transform lives
/// on this side too.
SceneDocument sceneFromWire(Map<String, Object?> root) =>
    SceneDocument(_nodeFromWire(root) as FrameNode);

SceneNode _nodeFromWire(Map<String, Object?> json) {
  var name = '${json['name']}';
  double? number(String key) => (json[key] as num?)?.toDouble();
  SceneColor? color(String key) =>
      json[key] == null ? null : SceneColor((json[key]! as num).toInt());

  var node = switch (json['kind']) {
    'text' =>
      TextNode(name, '${json['text']}')
        ..fontSize = number('fontSize') ?? 16
        ..weight =
            SceneFontWeight.values[(json['weight'] as num?)?.toInt() ?? 3]
        ..color = color('color') ?? const SceneColor(0xFF1A1A1A),
    'shape' => ShapeNode(name, circle: json['circle'] == true),
    'ext' => ExternalNode(
      name,
      '${json['entry']}',
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    _ =>
      FrameNode(
          name,
          layout: NodeLayout.values.byName('${json['layout'] ?? 'absolute'}'),
        )
        ..gap = number('gap') ?? 8
        ..padding = number('padding') ?? 0
        ..crossAlign = SceneCrossAxisAlignment
            .values[(json['crossAlign'] as num?)?.toInt() ?? 2]
        ..children.addAll([
          for (var c in (json['children'] as List? ?? const []))
            _nodeFromWire((c as Map).cast<String, Object?>()),
        ]),
  };

  node
    ..x = number('x') ?? 0
    ..y = number('y') ?? 0
    ..width = number('w')
    ..height = number('h')
    ..fill = color('fill')
    ..cornerRadius = number('corner') ?? 0
    ..opacity = number('opacity') ?? 1;

  if (json['fx'] case List fx when fx.length == 4) {
    double at(int i) => (fx[i] as num).toDouble();
    node.effect()
      ..translateX = at(0)
      ..translateY = at(1)
      ..scale = at(2)
      ..rotate = at(3);
  }
  return node;
}
