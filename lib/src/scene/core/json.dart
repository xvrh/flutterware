// The model as data, both ways.
//
// Two shapes, deliberately different. The WIRE (`SceneDocument.toWire`) is a
// picture: rendered values, fx folded in, selection along for the ride — what
// the editor pushes at a live guest sixty times a second. This file is the
// other one: the AUTHORED document, exactly what the file says, which is what
// a guest needs when it is going to evaluate the motion itself rather than be
// fed frames — an export walking a playhead in a tester, or an app mounting a
// scene it was handed.
import 'curves.dart';
import 'model.dart';
import 'motion_model.dart';
import 'values.dart';

SceneTextAlign _textAlign(Object? raw) => switch (raw) {
  num i when i >= 0 && i < SceneTextAlign.values.length =>
    SceneTextAlign.values[i.toInt()],
  _ => SceneTextAlign.left,
};

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
          scene: scene,
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
  if (n.width != null) 'w': sizeToWire(n.width),
  if (n.height != null) 'h': sizeToWire(n.height),
  if (n.fill != null) 'fill': n.fill!.argb,
  if (n.borderColor case var b?) 'border': [b.argb, n.borderWidth],
  if (n.corner != 0) 'corner': n.corner,
  if (n.opacity != 1) 'opacity': n.opacity,
  'repeat': ?n.repeat,
  if (n.paramRefs.isNotEmpty) 'paramRefs': {...n.paramRefs},
  ...switch (n) {
    FrameNode f => {
      'layout': f.layout.name,
      'gap': f.gap,
      'padding': f.padding.toWire(),
      if (f.columns.isNotEmpty)
        'columns': [for (var c in f.columns) sizeToWire(c)],
      if (!f.cellPadding.isZero) 'cellPadding': f.cellPadding.toWire(),
      'mainAlign': f.mainAlign.name,
      'crossAlign': f.crossAlign.name,
      'children': [for (var c in f.children) _nodeToJson(c)],
    },
    TextNode t => {
      'text': t.text,
      'fontSize': t.fontSize,
      'weight': t.weight.index,
      'color': t.color.argb,
      if (t.align != SceneTextAlign.left) 'align': t.align.index,
      if (t.maxLines != null) 'maxLines': ?t.maxLines,
    },
    ShapeNode s => {'circle': s.circle},
    ExternalNode e => {
      'entry': e.entry,
      'args': {...e.args},
    },
    SceneRefNode r => {
      'scene': r.sceneClassName,
      'args': {...r.args},
    },
  },
};

SceneNode _nodeFromJson(Map<String, Object?> json) {
  var name = json['name']! as String;
  double? number(String key) => (json[key] as num?)?.toDouble();
  var node = switch (json['kind']) {
    'Frame' =>
      FrameNode(
          name: name,
          layout: NodeLayout.values.byName(json['layout']! as String),
        )
        ..gap = number('gap') ?? 8
        ..padding = SceneEdges.fromWire(json['padding'])
        ..columns = _columns(json['columns'])
        ..cellPadding = SceneEdges.fromWire(json['cellPadding'])
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
      TextNode(json['text']! as String, name: name)
        ..fontSize = number('fontSize') ?? 16
        ..weight =
            SceneFontWeight.values[(json['weight'] as num?)?.toInt() ?? 3]
        ..color = SceneColor((json['color'] as num?)?.toInt() ?? 0xFF1A1A1A)
        ..align = _textAlign(json['align'])
        ..maxLines = (json['maxLines'] as num?)?.toInt(),
    'Shape' => ShapeNode(name: name, circle: json['circle'] == true),
    'Ext' => ExternalNode(
      json['entry']! as String,
      name: name,
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    'Scene' => SceneRefNode(
      json['scene']! as String,
      name: name,
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    _ => throw ArgumentError('unknown node kind "${json['kind']}"'),
  };
  return node
    ..x = number('x') ?? 0
    ..y = number('y') ?? 0
    ..width = sizeFromWire(json['w'])
    ..height = sizeFromWire(json['h'])
    ..fill = json['fill'] == null
        ? null
        : SceneColor((json['fill']! as num).toInt())
    ..borderColor = switch (json['border']) {
      List l when l.isNotEmpty => SceneColor((l[0] as num).toInt()),
      _ => null,
    }
    ..borderWidth = switch (json['border']) {
      List l when l.length > 1 => (l[1] as num).toDouble(),
      _ => 1,
    }
    ..corner = number('corner') ?? 0
    ..opacity = number('opacity') ?? 1
    ..repeat = json['repeat'] as String?
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
          'target': g.node.name,
          'tracks': {
            for (var e in g.tracks.entries) e.key: _trackToJson(e.value),
          },
          'args': {for (var e in g.args.entries) e.key: _trackToJson(e.value)},
        },
    ],
    'timeline': _exprToJson(timeline),
  };
}

/// The inverse of [MotionDocumentJson.toJson].
///
/// [scene] is required because a group holds the NODE it animates, and JSON
/// can only carry the name — so this is the one place a name becomes a node
/// again, and it is a read of something the editor wrote.
MotionDocument motionFromJson(
  Map<String, Object?> json, {
  required String sceneClassName,
  required SceneDocument scene,
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
    var target = g['target']! as String;
    var node = scene.nodeNamed(target);
    if (node == null) {
      throw ArgumentError(
        'the motion animates "$target", which this scene does not declare',
      );
    }
    var group = AnimateGroup(node, name: g['name']! as String);
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
    doc,
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
        if (k.curve case var curve?) 'curve': curve.name,
        if (k.paramRef != null) 'paramRef': k.paramRef,
      },
  ],
};

MotionTrack _trackFromJson(Map<String, Object?> json) {
  var kind = TrackKind.values.byName(json['kind']! as String);
  return MotionTrack([
    for (var raw in (json['keys'] as List? ?? const []))
      if ((raw as Map).cast<String, Object?>() case var k)
        MotionKey(
          at: Duration(microseconds: (k['at']! as num).toInt()),
          value: kind == TrackKind.color
              ? SceneColor((k['value']! as num).toInt())
              : (k['value']! as num).toDouble(),
          curve: sceneCurvesByName[k['curve']],
          paramRef: k['paramRef'] as String?,
        ),
  ], kind: kind);
}

Map<String, Object?> _exprToJson(TimelineExpr e) => switch (e) {
  // A placed group travels as its name, which is all JSON can carry; the
  // read side puts it back to the group itself.
  AnimateGroup g => {'op': 'ref', 'name': g.name},
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

TimelineExpr _exprFromJson(Map<String, Object?> json, MotionDocument doc) {
  List<TimelineExpr> children() => [
    for (var c in (json['children'] as List? ?? const []))
      _exprFromJson((c as Map).cast<String, Object?>(), doc),
  ];
  TimelineExpr child() =>
      _exprFromJson((json['child']! as Map).cast<String, Object?>(), doc);
  return switch (json['op']) {
    'ref' =>
      doc.groupNamed(json['name']! as String) ??
          (throw ArgumentError(
            'the timeline places "${json['name']}", which is not a group here',
          )),
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
  List items => [
    for (var item in items) {...item as Map},
  ],
  _ => value,
};

/// Column tracks, in the same three-valued spelling as a node's size.
List<double?> _columns(Object? raw) => switch (raw) {
  List l => [for (var c in l) sizeFromWire(c)],
  _ => <double?>[],
};

/// A parameter's default, read back as the kind it was declared with — an
/// int in the file is a colour or a number depending on the hole it fills.
Object _paramValue(SceneParamKind kind, Object? raw) => switch (kind) {
  SceneParamKind.color => SceneColor((raw! as num).toInt()),
  SceneParamKind.number => (raw! as num).toDouble(),
  SceneParamKind.string => raw! as String,
  // A list's items are string and number fields only, so JSON carries them
  // as they are — the one parameter default that needs no reviving.
  SceneParamKind.list => [
    for (var item in raw! as List)
      <String, Object>{
        for (var e in (item as Map).entries)
          '${e.key}': e.value is num
              ? (e.value as num).toDouble()
              : '${e.value}',
      },
  ],
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
      TextNode('${json['text']}', name: name)
        ..fontSize = number('fontSize') ?? 16
        ..weight =
            SceneFontWeight.values[(json['weight'] as num?)?.toInt() ?? 3]
        ..color = color('color') ?? const SceneColor(0xFF1A1A1A)
        ..align = _textAlign(json['align'])
        ..maxLines = (json['maxLines'] as num?)?.toInt(),
    'shape' => ShapeNode(name: name, circle: json['circle'] == true),
    'ext' => ExternalNode(
      '${json['entry']}',
      name: name,
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    _ =>
      FrameNode(
          name: name,
          layout: NodeLayout.values.byName('${json['layout'] ?? 'absolute'}'),
        )
        ..gap = number('gap') ?? 8
        ..padding = SceneEdges.fromWire(json['padding'])
        ..columns = _columns(json['columns'])
        ..cellPadding = SceneEdges.fromWire(json['cellPadding'])
        ..mainAlign = SceneMainAxisAlignment
            .values[(json['mainAlign'] as num?)?.toInt() ?? 0]
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
    ..width = sizeFromWire(json['w'])
    ..height = sizeFromWire(json['h'])
    ..fill = color('fill')
    ..borderColor = switch (json['border']) {
      List l when l.isNotEmpty => SceneColor((l[0] as num).toInt()),
      _ => null,
    }
    ..borderWidth = switch (json['border']) {
      List l when l.length > 1 => (l[1] as num).toDouble(),
      _ => 1,
    }
    ..corner = number('corner') ?? 0
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
