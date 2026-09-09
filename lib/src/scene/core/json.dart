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
import 'props.dart';
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
          scene: scene,
        ),
    },
  );
}

extension SceneDocumentJson on SceneDocument {
  /// The authored plane, complete: parameters, nodes, and what each bound
  /// property reads. Never the fx plane, which belongs to its writers.
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
  // The parameters are in hand now, so a recorded repeat can become the
  // closure everything draws through.
  bindRepeats(doc);
  return doc;
}

/// The authored plane of one node: the table's properties off their
/// defaults, the bindings, and the structure the table does not hold —
/// children, a repeat, an external's or a scene's arguments.
Map<String, Object?> _nodeToJson(SceneNode n) => {
  'name': n.name,
  'kind': n.typeName,
  for (var p in scenePropsOf(n))
    if (p.onWire)
      if (p.read(n) case var v when !isSceneDefault(p, v)) p.key: p.toWire(v),
  if (n.bindings.isNotEmpty)
    'bindings': {for (var e in n.bindings.entries) e.key: e.value.toWire()},
  ...switch (n) {
    FrameNode f => {
      // Only the binding travels, never the closure: what a reader can
      // record is which parameter the rows came from.
      if (f.repeated?.source case var source? when source.isNotEmpty)
        'repeat': source,
      'children': [for (var c in f.children) _nodeToJson(c)],
    },
    TextNode() || ShapeNode() => <String, Object?>{},
    ExternalNode e => {
      'entry': e.entry,
      'args': {...e.args},
    },
    SceneRefNode r => {
      'scene': r.sceneClassName,
      'tokensArg': ?r.tokensArg,
      'args': {...r.args},
    },
  },
};

SceneNode _nodeFromJson(Map<String, Object?> json) {
  var name = json['name']! as String;
  var node = switch (json['kind']) {
    'Frame' =>
      FrameNode(name: name)
        ..repeated = switch (json['repeat']) {
          String source => SceneRepeat(
            items: const [],
            source: source,
            row: (_) => const [],
          ),
          _ => null,
        }
        ..children.addAll([
          for (var c in (json['children'] as List? ?? const []))
            _nodeFromJson((c as Map).cast<String, Object?>()),
        ]),
    'Text' => TextNode('', name: name),
    'Shape' => ShapeNode(name: name),
    'Ext' => ExternalNode.read(
      json['entry']! as String,
      name: name,
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    'Scene' => SceneRefNode.read(
      json['scene']! as String,
      name: name,
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    )..tokensArg = json['tokensArg'] as String?,
    _ => throw ArgumentError('unknown node kind "${json['kind']}"'),
  };
  readSceneProps(node, json);
  node.bindings.addAll(
    ((json['bindings'] as Map?) ?? const {}).map(
      (k, v) => MapEntry('$k', SceneBinding.fromWire('$v')),
    ),
  );
  return node;
}

/// Every table property of [node] off [json], the default where the key is
/// absent — shared by the authored plane and the wire, which spell values
/// the same way and differ only in what else they carry.
void readSceneProps(SceneNode node, Map<String, Object?> json) {
  for (var p in scenePropsOf(node)) {
    if (!p.onWire) continue;
    // A legacy payload packed the border as [argb, width].
    if (p.name == 'borderColor' && json['border'] is List) {
      var l = json['border']! as List;
      node.borderColor = l.isNotEmpty
          ? SceneColor((l[0] as num).toInt())
          : null;
      node.borderWidth = l.length > 1 ? (l[1] as num).toDouble() : 1;
      continue;
    }
    if (p.name == 'borderWidth' && json.containsKey('border')) continue;
    var raw = json[p.key];
    if (raw == null && !json.containsKey(p.key)) {
      // Missing means default — except where null IS the value.
      if (p.kind != ScenePropKind.size && p.kind != ScenePropKind.integer) {
        p.write(node, p.defaultValue);
        continue;
      }
    }
    p.write(node, p.fromWire(raw));
  }
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

/// A parameter's default, read back as the kind it was declared with — an
/// int in the file is a colour or a number depending on the hole it fills.
Object _paramValue(SceneParamKind kind, Object? raw) => switch (kind) {
  SceneParamKind.color => SceneColor((raw! as num).toInt()),
  SceneParamKind.number => (raw! as num).toDouble(),
  SceneParamKind.string => raw! as String,
  SceneParamKind.bool => raw! as bool,
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
  var node = switch (json['kind']) {
    'text' => TextNode('', name: name),
    'shape' => ShapeNode(name: name),
    'ext' => ExternalNode.read(
      '${json['entry']}',
      name: name,
      args: ((json['args'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    _ =>
      FrameNode(name: name)
        ..children.addAll([
          for (var c in (json['children'] as List? ?? const []))
            _nodeFromWire((c as Map).cast<String, Object?>()),
        ]),
  };
  readSceneProps(node, json);
  // Which properties read the app's own values — kept as bindings, so the
  // host resolves them against the exports it holds (`bindExternals`).
  if (json['exports'] case Map exports) {
    for (var e in exports.entries) {
      var prop = '${e.key}';
      node.bindings[prop] =
          resolveSceneKey(node, prop)?.prop.kind == ScenePropKind.style
          ? StyleRef('${e.value}')
          : TokenRef('${e.value}');
    }
  }

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
