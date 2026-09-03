// Disposable spike: the motion class grammar, its parser and its emitter —
// the scene grammar's discipline applied to the motion rewrite (sketches
// 17–25, decisions owner-signed 2026-09-01).
//
// THE GRAMMAR, on a page. A motion is a class in the SCENE file, beside
// the scene it animates (grammar 0.5 folded the two files into one, so
// there is no marker and no file of its own here — scene_file.dart is the
// door). A motion class is:
//       class <Name>(super.scene, {final double p = 24, …})
//           extends SceneMotion<SceneClass> { … }
//     — the primary constructor's first formal is `super.scene`; each other
//     formal is a motion parameter (`final <double|String|Color> <name> =
//     <literal>`, exactly the scene's parameter spelling); the extends
//     clause names the scene this motion animates
//   - group fields: `late final <name> = scene.<node>.animate(…)` — THE
//     FIELD NAME IS THE GROUP'S IDENTITY, the target is the scene node's
//     own field name (typed in real Dart, resolved against the scene here),
//     and the named arguments are that node kind's animatable properties,
//     each a `Track([Key(…), …])`; an external node additionally takes
//     `args: {'<arg>': Track(…)}` — the grammar's one stringly boundary
//   - a Key is `Key(at: <int>.ms, value: <literal or parameter name>,
//     curve: Curves.<allowlisted>)` — keys time-sorted, times unique,
//     tracks non-empty (Save writes no empty tracks)
//   - a mandatory `late final timeline = <arrangement>` — Par/Seq lists,
//     At(<int>.ms, …), Speed(<number>, …), Repeat(<int>, …) over group
//     names; a group placed at most once; an UNPLACED group is a library
//     asset (independently playable, no autoplay), not an orphan
//   - a derived `copy` member the tool maintains:
//       <Name> copy(<SceneClass> scene) =>
//           copyStateInto(<Name>(scene, p: p, …));
//     a missing or stale copy is tolerated and converged on the next emit;
//     any other shape is refused
//   - nothing else — same refusal policy as the scene: collected,
//     all-or-nothing, with a line number, never silently dropped.
//
// Invariants the tests hold: parse(emit(model)) succeeds and re-emits
// identically; emit ∘ parse is the identity on canonical files; accepted
// non-canonical spellings (`final` for `late final`, `Curves.linear`,
// a missing or stale `copy`, a type-less parameter formal) converge in one
// emit; every hostile construct is refused with an offset and a name.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:flutterware/scene_authoring.dart';

import 'scene_file.dart' show SceneRefusal;

/// The curves a key may name — canonical spelling `Curves.<name>`; `linear`
/// is accepted and converges to no curve at all.
const motionCurves = [
  'linear',
  'ease',
  'easeIn',
  'easeOut',
  'easeInOut',
  'easeInBack',
  'easeOutBack',
  'easeInCubic',
  'easeOutCubic',
  'decelerate',
  'fastOutSlowIn',
  'bounceOut',
  'elasticOut',
];

class MotionParse {
  MotionParse(this.doc, this.className, this.refusals);

  final MotionDocument? doc;
  final String? className;
  final List<SceneRefusal> refusals;

  bool get ok => doc != null;
}

// ---------------------------------------------------------------------------
// Emit
// ---------------------------------------------------------------------------

/// Write one motion class into the scene file being emitted — a motion is
/// half a pair and has no file of its own (grammar 0.5).
void emitMotionClass(
  StringBuffer out,
  MotionDocument doc,
  SceneDocument scene, {
  required String className,
}) {
  var seen = <String>{...motionReservedNames};
  var params = <String, SceneParamDecl>{};
  for (var p in doc.params) {
    if (!isValidNodeName(p.name) || !seen.add(p.name)) {
      throw ArgumentError('"${p.name}" is not a usable parameter name');
    }
    params[p.name] = p;
  }
  out.write('class $className(super.scene');
  if (doc.params.isNotEmpty) {
    out.write(', {');
    for (var p in doc.params) {
      out.write('final ${p.typeName} ${p.name} = ${_paramDefault(p)}, ');
    }
    out.write('}');
  }
  out.writeln(') extends SceneMotion<${doc.sceneClassName}> {');
  for (var g in doc.groups) {
    if (!isValidNodeName(g.name) || !seen.add(g.name)) {
      throw ArgumentError(
        '"${g.name}" is not a usable group name — names are field names: '
        'valid identifiers, unique in the class, off the reserved list',
      );
    }
    var target = scene.nodeNamed(g.target);
    if (target == null) {
      throw ArgumentError('"${g.target}" is not a node in this scene');
    }
    out.write('  late final ${g.name} = scene.${g.target}.animate(');
    for (var ScenePropSpec(name: prop, :kind) in animatableProps(target)) {
      var track = g.tracks[prop];
      if (track == null) continue;
      out.write('$prop: ${_track(track, kind, params)}, ');
    }
    if (g.args.isNotEmpty) {
      var keys = g.args.keys.toList()..sort();
      out.write('args: {');
      for (var key in keys) {
        out.write(
          '${_str(key)}: ${_track(g.args[key]!, TrackKind.number, params)}, ',
        );
      }
      out.write('}, ');
    }
    out.writeln(');');
  }
  out.writeln('  late final timeline = ${_expr(doc.timeline)};');
  out.write('  $className copy(${doc.sceneClassName} scene) => ');
  out.write('copyStateInto($className(scene');
  for (var p in doc.params) {
    out.write(', ${p.name}: ${p.name}');
  }
  out.writeln('));');
  out.writeln('}');
}

String _track(MotionTrack t, TrackKind kind, Map<String, SceneParamDecl> ps) {
  if (t.keys.isEmpty) {
    throw ArgumentError(
      'a track with no keys is not written — Save writes non-empty tracks '
      'only; remove the property instead',
    );
  }
  if (t.kind != kind) {
    throw ArgumentError('this property takes a ${kind.name} track');
  }
  var keys = t.keys.map((k) {
    var parts = ['at: ${_dur(k.at)}'];

    // A parameter reference survives a save only while the key still holds
    // the parameter's default — an edited value bakes in and the stale
    // reference is dropped, never the edit.
    var p = k.paramRef == null ? null : ps[k.paramRef];
    if (p != null && p.defaultValue == k.value) {
      parts.add('value: ${k.paramRef}');
    } else {
      parts.add(
        'value: ${kind == TrackKind.color ? _color(k.value as SceneColor) : _num((k.value as num).toDouble())}',
      );
    }
    if (k.curve case var curve? when curve != 'linear') {
      if (!motionCurves.contains(curve)) {
        throw ArgumentError('"$curve" is not an allowlisted curve');
      }
      parts.add('curve: Curves.$curve');
    }
    return 'Key(${parts.join(', ')})';
  });
  return 'Track([${keys.join(', ')}])';
}

String _expr(TimelineExpr e) => switch (e) {
  GroupRef r => r.name,
  ParExpr p => 'Par([${p.children.map(_expr).join(', ')}])',
  SeqExpr s => 'Seq([${s.children.map(_expr).join(', ')}])',
  AtExpr a => 'At(${_dur(a.offset)}, ${_expr(a.child)})',
  SpeedExpr s => 'Speed(${_num(s.factor)}, ${_expr(s.child)})',
  RepeatExpr r => 'Repeat(${r.times}, ${_expr(r.child)})',
};

String _dur(Duration d) {
  if (d.isNegative || d.inMicroseconds % 1000 != 0) {
    throw ArgumentError(
      'a motion time is a whole, non-negative millisecond '
      'count — got $d',
    );
  }
  return '${d.inMilliseconds}.ms';
}

String _paramDefault(SceneParamDecl p) => switch (p.kind) {
  SceneParamKind.string => _str(p.defaultValue as String),
  SceneParamKind.number => _num(p.defaultValue as double),
  SceneParamKind.color => 'const ${_color(p.defaultValue as SceneColor)}',
  // A track interpolates between two values; a list is not one.
  SceneParamKind.list => throw ArgumentError(
    'a motion parameter cannot be a list — "${p.name}"',
  ),
};

String _num(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15 ? '${v.round()}' : '$v';

String _color(SceneColor c) =>
    'Color(0x${c.argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';

String _str(String s) {
  var out = StringBuffer("'");
  for (var rune in s.runes) {
    switch (rune) {
      case 0x5C:
        out.write(r'\\');
      case 0x27:
        out.write(r"\'");
      case 0x24:
        out.write(r'\$');
      case 0x0A:
        out.write(r'\n');
      case 0x0D:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        out.writeCharCode(rune);
    }
  }
  out.write("'");
  return '$out';
}

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

/// Parses [source] against the scene it animates: targets resolve to
/// [scene]'s nodes, and the extends clause must name [sceneClassName] —
/// a motion is one half of a pair, never read alone.
/// Read one motion class out of the scene file the door already parsed —
/// targets resolve against [scene], which the door parsed first.
MotionParse parseMotionClass(
  ClassDeclaration decl,
  String source, {
  required SceneDocument scene,
  required String sceneClassName,
}) {
  var p = _Parser(source, scene, sceneClassName);
  var doc = p.parseClass(decl);
  return MotionParse(p.refusals.isEmpty ? doc : null, p.className, p.refusals);
}

class _Parser {
  _Parser(this.source, this.scene, this.sceneClassName);

  final String source;
  final SceneDocument scene;
  final String sceneClassName;
  final refusals = <SceneRefusal>[];
  String? className;
  late final _lines = source.split('\n');

  final _params = <String, SceneParamDecl>{};

  void refuse(int offset, String construct, String message) {
    var line = 1;
    var seen = 0;
    for (var l in _lines) {
      if (offset <= seen + l.length) break;
      seen += l.length + 1;
      line++;
    }
    refusals.add(SceneRefusal(offset, line, construct, message));
  }

  MotionDocument? parseClass(ClassDeclaration found) {
    className = found.namePart.typeName.lexeme;
    _refuseComments(found);
    _readHeader(found);

    // Phase 1: members. Groups collect; the timeline is read as an
    // expression tree of references, linked after every group is known
    // (forward references are ordinary under `late final`).
    var doc = MotionDocument(sceneClassName: sceneClassName);
    var declared = <String, int>{
      for (var n in motionReservedNames) n: -1,
      for (var p in _params.keys) p: -1,
    };
    (TimelineExpr, int)? timeline;
    var refOffsets = <GroupRef, int>{};
    for (var member in found.body.members) {
      if (member is ConstructorDeclaration) {
        refuse(
          member.offset,
          'constructor',
          'parameters live in the class header — '
              '`class ${className!}(super.scene, {final double p = 1})`',
        );
        continue;
      }
      if (member is MethodDeclaration && member.name.lexeme == 'copy') {
        _checkCopy(member);
        continue;
      }
      if (member is! FieldDeclaration || member.fields.variables.length != 1) {
        refuse(
          member.offset,
          'member',
          'the motion class holds group fields, the timeline, and the '
              'derived copy — nothing else',
        );
        continue;
      }
      var variable = member.fields.variables.single;
      var name = variable.name.lexeme;
      var initializer = variable.initializer;
      if (initializer == null) {
        refuse(member.offset, 'no initializer', '`$name` must be initialized');
        continue;
      }
      if (name == 'timeline') {
        if (timeline != null) {
          refuse(
            variable.offset,
            'duplicate name',
            'timeline is declared twice',
          );
          continue;
        }
        var expr = _timeline(initializer, refOffsets);
        if (expr != null) timeline = (expr, variable.offset);
        continue;
      }
      if (declared.containsKey(name)) {
        refuse(
          variable.offset,
          'duplicate name',
          motionReservedNames.contains(name)
              ? '"$name" is reserved in a motion class'
              : '"$name" is already declared — parameters and groups share '
                    'one namespace, and a name is an identity',
        );
        continue;
      }
      declared[name] = variable.offset;
      var group = _group(name, initializer);
      if (group != null) doc.groups.add(group);
    }

    // Phase 2: link. The timeline is mandatory; every reference resolves to
    // a declared group and appears at most once. An UNPLACED group is a
    // library asset by decision — playable on events, no autoplay — so
    // there is no orphan refusal here.
    if (timeline == null) {
      if (refusals.isEmpty) {
        refuse(
          found.offset,
          'no timeline',
          'the motion class declares `late final timeline = Par([…])` — '
              'the timeline is what plays',
        );
      }
      return null;
    }
    var placed = <String>{};
    for (var entry in refOffsets.entries) {
      var name = entry.key.name;
      if (_params.containsKey(name)) {
        refuse(
          entry.value,
          'parameter in timeline',
          '"$name" is a parameter — the timeline plays groups',
        );
        continue;
      }
      if (doc.groupNamed(name) == null) {
        refuse(
          entry.value,
          'unknown reference',
          '"$name" is not a group declared in this motion',
        );
        continue;
      }
      if (!placed.add(name)) {
        refuse(
          entry.value,
          'placed twice',
          '"$name" is already in the timeline — a group plays from one '
              'place; wrap it in Repeat or split the group instead',
        );
      }
    }
    doc.timeline = timeline.$1;
    doc.params.addAll(_params.values);
    return doc;
  }

  /// The class header: `(super.scene, {…params})` and
  /// `extends SceneMotion<Scene>`.
  void _readHeader(ClassDeclaration decl) {
    var extendsClause = decl.extendsClause;
    var superType = extendsClause?.superclass;
    if (superType == null || superType.name.lexeme != 'SceneMotion') {
      refuse(
        decl.offset,
        'extends',
        'a motion class extends SceneMotion<$sceneClassName>',
      );
    } else {
      var args = superType.typeArguments?.arguments;
      var arg = args?.length == 1 ? args!.single : null;
      var named = arg is NamedType ? arg.name.lexeme : null;
      if (named != sceneClassName) {
        refuse(
          superType.offset,
          'scene class',
          'this motion extends SceneMotion<${named ?? '…'}> but the scene '
              'beside it is $sceneClassName',
        );
      }
    }
    if (decl.withClause != null || decl.implementsClause != null) {
      refuse(
        (decl.withClause ?? decl.implementsClause)!.offset,
        'clause',
        'a motion class only extends SceneMotion',
      );
    }
    if (decl.namePart case PrimaryConstructorDeclaration pc) {
      if (pc.constKeyword != null) {
        refuse(
          pc.constKeyword!.offset,
          'const',
          'a motion is never const — its groups are late finals',
        );
      }
      var sawScene = false;
      for (var p in pc.formalParameters.parameters) {
        if (p is SuperFormalParameter && p.name.lexeme == 'scene') {
          sawScene = true;
          continue;
        }
        _readParam(p);
      }
      if (!sawScene) {
        refuse(
          pc.formalParameters.offset,
          'scene formal',
          'the first formal is `super.scene` — the motion holds the scene '
              'it animates',
        );
      }
    } else {
      refuse(
        decl.offset,
        'no constructor',
        'a motion class takes its scene in the header — '
            '`class ${className!}(super.scene) extends '
            'SceneMotion<$sceneClassName>`',
      );
    }
  }

  void _readParam(FormalParameter p) {
    var name = p.name?.lexeme;
    if (p is FieldFormalParameter) {
      refuse(
        p.offset,
        'parameter',
        'a motion parameter is spelled in full in the header — '
            '`final double $name = 24` — never `this.`',
      );
      return;
    }
    if (!p.isNamed || name == null) {
      refuse(
        p.offset,
        'parameter',
        'after `super.scene`, a parameter is a named header formal with a '
            'default — `final double slideFrom = 24`',
      );
      return;
    }
    var dflt = p.defaultClause?.value;
    if (dflt == null) {
      refuse(p.offset, 'no default', 'a parameter carries a default value');
      return;
    }
    if (_params.containsKey(name) || motionReservedNames.contains(name)) {
      refuse(
        p.offset,
        'duplicate name',
        motionReservedNames.contains(name)
            ? '"$name" is reserved in a motion class'
            : '"$name" is declared twice',
      );
      return;
    }
    var parsed = _paramDefaultOf(dflt);
    if (parsed == null) {
      refuse(
        dflt.offset,
        'parameter default',
        'a default is a string, number or Color(0x…) literal',
      );
      return;
    }
    var decl = SceneParamDecl(name, parsed.$1, parsed.$2);
    if (p is RegularFormalParameter &&
        p.type != null &&
        '${p.type}' != decl.typeName) {
      refuse(
        p.type!.offset,
        'parameter type',
        'this default makes "$name" a ${decl.typeName} — spell it '
            '`final ${decl.typeName} $name`',
      );
      return;
    }
    _params[name] = decl;
  }

  (SceneParamKind, Object)? _paramDefaultOf(Expression e) {
    var inner = e;
    var negate = false;
    if (inner is PrefixExpression && inner.operator.lexeme == '-') {
      negate = true;
      inner = inner.operand;
    }
    switch (inner) {
      case SimpleStringLiteral(:var value):
        return (SceneParamKind.string, value);
      case IntegerLiteral(:var value?):
        return (SceneParamKind.number, (negate ? -value : value).toDouble());
      case DoubleLiteral(:var value):
        return (SceneParamKind.number, negate ? -value : value);
      default:
        if (_invocation(inner) case ('Color', var args)
            when args.arguments.length == 1) {
          var v = args.arguments.single.argumentExpression;
          if (v is IntegerLiteral && v.value != null) {
            return (SceneParamKind.color, SceneColor(v.value!));
          }
        }
        return null;
    }
  }

  /// `copy` is derived: a stale parameter list inside is tolerated (the
  /// next emit converges it), but the shape must be the canonical single
  /// expression, or the member is refused.
  void _checkCopy(MethodDeclaration m) {
    var body = m.body;
    var ok = false;
    if (body is ExpressionFunctionBody) {
      if (_invocation(body.expression) case ('copyStateInto', var args)
          when args.arguments.length == 1) {
        var inner = args.arguments.single.argumentExpression;
        if (_invocation(inner) case (var name, _) when name == className) {
          ok = true;
        }
      }
    }
    if (!ok) {
      refuse(
        m.offset,
        'copy',
        'copy is derived — the editor rewrites it as '
            '`${className!} copy($sceneClassName scene) => '
            'copyStateInto(${className!}(scene, …));`; leave it out or keep '
            'that shape',
      );
    }
  }

  void _refuseComments(ClassDeclaration decl) {
    var body = decl.body;
    if (body is! BlockClassBody) return;
    var start = body.leftBracket.offset;
    var end = decl.endToken.offset;
    for (
      Token? token = body.leftBracket;
      token != null && token.offset <= end;
      token = token.next
    ) {
      for (
        Token? comment = token.precedingComments;
        comment != null;
        comment = comment.next
      ) {
        if (comment.offset > start) {
          refuse(
            comment.offset,
            'comment',
            'comments inside the motion are not preserved by the editor, so '
                'they are refused rather than silently lost on the next save',
          );
        }
      }
      if (token.offset >= end) break;
    }
  }

  /// One group field: `scene.<node>.animate(<props…>)`.
  AnimateGroup? _group(String name, Expression expr) {
    String? targetName;
    ArgumentList? args;
    if (expr
        case MethodInvocation(:var methodName, :var target, :var argumentList)
        when methodName.name == 'animate') {
      if (target case PrefixedIdentifier(:var prefix, :var identifier)
          when prefix.name == 'scene') {
        targetName = identifier.name;
        args = argumentList;
      }
    }
    if (targetName == null || args == null) {
      refuse(
        expr.offset,
        'expression',
        'a group animates one scene node — '
            '`late final $name = scene.<node>.animate(…)`',
      );
      return null;
    }
    var target = scene.nodeNamed(targetName);
    if (target == null) {
      refuse(
        expr.offset,
        'unknown target',
        '"$targetName" is not a node in $sceneClassName',
      );
      return null;
    }
    var group = AnimateGroup(name, targetName);
    var allowed = {
      for (var spec in animatableProps(target)) spec.name: spec.kind,
    };
    for (var arg in args.arguments) {
      if (arg is! NamedArgument) {
        refuse(
          arg.offset,
          'positional argument',
          'a group takes only named track properties',
        );
        continue;
      }
      var prop = arg.name.lexeme;
      var value = arg.argumentExpression;
      if (prop == 'args') {
        if (target is! ExternalNode) {
          refuse(
            value.offset,
            'args',
            'only an external node takes args — "$targetName" is a '
                '${target.typeName}',
          );
          continue;
        }
        _extArgs(group, value);
        continue;
      }
      var kind = allowed[prop];
      if (kind == null) {
        refuse(
          value.offset,
          'unknown property',
          '"$prop" is not animatable on a ${target.typeName} — '
              '${allowed.keys.join(', ')}',
        );
        continue;
      }
      var track = _trackOf(value, kind);
      if (track != null) group.tracks[prop] = track;
    }
    return group;
  }

  void _extArgs(AnimateGroup group, Expression e) {
    if (e is! SetOrMapLiteral) {
      refuse(e.offset, 'args', 'args takes a map of tracks by arg name');
      return;
    }
    for (var element in e.elements) {
      if (element is! MapLiteralEntry) {
        refuse(element.offset, 'args', 'expected a literal entry');
        continue;
      }
      var key = element.key;
      if (key is! SimpleStringLiteral) {
        refuse(key.offset, _kind(key), 'an arg name is a string literal');
        continue;
      }
      var track = _trackOf(element.value, TrackKind.number);
      if (track != null) group.args[key.value] = track;
    }
  }

  MotionTrack? _trackOf(Expression e, TrackKind kind) {
    ListLiteral? list;
    if (_invocation(e) case ('Track', var args)
        when args.arguments.length == 1) {
      var only = args.arguments.single.argumentExpression;
      if (only is ListLiteral) list = only;
    }
    if (list == null) {
      refuse(e.offset, _kind(e), 'a property is a Track([Key(…), …])');
      return null;
    }
    if (list.elements.isEmpty) {
      refuse(
        list.offset,
        'empty track',
        'a track with no keys contributes nothing and is never written — '
            'remove the property instead',
      );
      return null;
    }
    var track = MotionTrack(kind);
    Duration? last;
    for (var element in list.elements) {
      if (element is! Expression) {
        refuse(element.offset, 'element', 'a track lists its keys one by one');
        continue;
      }
      var key = _keyOf(element, kind);
      if (key == null) continue;
      if (last != null && key.at < last) {
        refuse(
          element.offset,
          'keys out of order',
          'keys are listed in time order — the hold rule reads them sorted',
        );
        continue;
      }
      if (key.at == last) {
        refuse(
          element.offset,
          'duplicate key time',
          'two keys at ${key.at.inMilliseconds}.ms — one value per time',
        );
        continue;
      }
      last = key.at;
      track.keys.add(key);
    }
    return track.keys.isEmpty ? null : track;
  }

  MotionKey? _keyOf(Expression e, TrackKind kind) {
    ArgumentList? args;
    if (_invocation(e) case ('Key', var a)) args = a;
    if (args == null) {
      refuse(e.offset, _kind(e), 'expected Key(at: …, value: …)');
      return null;
    }
    Duration? at;
    Object? value;
    String? paramRef;
    String? curve;
    var before = refusals.length;
    for (var arg in args.arguments) {
      if (arg is! NamedArgument) {
        refuse(arg.offset, 'positional argument', 'Key takes named arguments');
        continue;
      }
      var v = arg.argumentExpression;
      switch (arg.name.lexeme) {
        case 'at':
          at = _durOf(v);
        case 'value':
          (value, paramRef) = _valueOf(v, kind) ?? (null, null);
        case 'curve':
          curve = _curveOf(v);
        default:
          refuse(
            v.offset,
            'unknown property',
            'Key has no property "${arg.name.lexeme}"',
          );
      }
    }
    if (at == null || value == null) {
      // A refusal inside an argument already told the story; only a key
      // with the arguments simply absent needs its own.
      if (refusals.length == before) {
        refuse(e.offset, 'key', 'a Key needs `at:` and `value:`');
      }
      return null;
    }
    return MotionKey(at: at, value: value, curve: curve, paramRef: paramRef);
  }

  Duration? _durOf(Expression e) {
    if (e case PropertyAccess(:var target, :var propertyName)
        when propertyName.name == 'ms' &&
            target is IntegerLiteral &&
            target.value != null) {
      return Duration(milliseconds: target.value!);
    }
    refuse(e.offset, _kind(e), 'a time is spelled `<int>.ms`');
    return null;
  }

  /// A value literal of the track's kind, or a declared parameter's name —
  /// which binds the key to the parameter and yields its default.
  (Object, String?)? _valueOf(Expression e, TrackKind kind) {
    if (e is SimpleIdentifier) {
      var decl = _params[e.name];
      if (decl == null) {
        refuse(
          e.offset,
          'identifier',
          '"${e.name}" is not a declared parameter',
        );
        return null;
      }
      var wanted = switch (kind) {
        TrackKind.number => SceneParamKind.number,
        TrackKind.color => SceneParamKind.color,
      };
      if (decl.kind != wanted) {
        refuse(
          e.offset,
          'parameter type',
          '"${e.name}" is a ${decl.typeName} parameter — this track holds '
              '${kind.name}s',
        );
        return null;
      }
      return (decl.defaultValue, e.name);
    }
    switch (kind) {
      case TrackKind.number:
        var v = _double(e);
        return v == null ? null : (v, null);
      case TrackKind.color:
        var v = _colorOf(e);
        return v == null ? null : (v, null);
    }
  }

  String? _curveOf(Expression e) {
    if (e is PrefixedIdentifier &&
        e.prefix.name == 'Curves' &&
        motionCurves.contains(e.identifier.name)) {
      var name = e.identifier.name;
      return name == 'linear' ? null : name;
    }
    refuse(
      e.offset,
      'unknown curve',
      'expected Curves.<${motionCurves.take(4).join('|')}…> — nothing else '
          'is on the allowlist',
    );
    return null;
  }

  /// The arrangement tree. References are collected with their offsets and
  /// validated after every group is known.
  TimelineExpr? _timeline(Expression e, Map<GroupRef, int> refOffsets) {
    if (e is SimpleIdentifier) {
      var ref = GroupRef(e.name);
      refOffsets[ref] = e.offset;
      return ref;
    }
    var (name, args) = _invocation(e) ?? (null, null);
    if (name == null || args == null) {
      refuse(
        e.offset,
        _kind(e),
        'the timeline arranges groups with Par, Seq, At, Speed and Repeat',
      );
      return null;
    }
    List<TimelineExpr>? children(int index) {
      var arg = args.arguments[index].argumentExpression;
      if (arg is! ListLiteral) {
        refuse(arg.offset, _kind(arg), '$name takes a list of arrangements');
        return null;
      }
      var out = <TimelineExpr>[];
      for (var element in arg.elements) {
        if (element is! Expression) {
          refuse(
            element.offset,
            'element',
            'arrangements are listed one by '
                'one',
          );
          continue;
        }
        var child = _timeline(element, refOffsets);
        if (child != null) out.add(child);
      }
      return out;
    }

    switch (name) {
      case 'Par' || 'Seq' when args.arguments.length == 1:
        var kids = children(0);
        if (kids == null) return null;
        return name == 'Par' ? ParExpr(kids) : SeqExpr(kids);
      case 'At' when args.arguments.length == 2:
        var offset = _durOf(args.arguments[0].argumentExpression);
        var child = _timeline(args.arguments[1].argumentExpression, refOffsets);
        if (offset == null || child == null) return null;
        return AtExpr(offset, child);
      case 'Speed' when args.arguments.length == 2:
        var factor = _double(args.arguments[0].argumentExpression);
        var child = _timeline(args.arguments[1].argumentExpression, refOffsets);
        if (factor == null || child == null) return null;
        if (factor <= 0) {
          refuse(
            args.arguments[0].offset,
            'speed factor',
            "a speed factor is positive — reversing is the player's job",
          );
          return null;
        }
        return SpeedExpr(factor, child);
      case 'Repeat' when args.arguments.length == 2:
        var timesExpr = args.arguments[0].argumentExpression;
        var times = timesExpr is IntegerLiteral ? timesExpr.value : null;
        var child = _timeline(args.arguments[1].argumentExpression, refOffsets);
        if (times == null) {
          refuse(
            timesExpr.offset,
            _kind(timesExpr),
            'Repeat counts with an '
            'int literal',
          );
          return null;
        }
        if (child == null) return null;
        if (times < 1) {
          refuse(
            timesExpr.offset,
            'repeat count',
            'Repeat plays at least '
                'once',
          );
          return null;
        }
        return RepeatExpr(times, child);
      case 'Par' || 'Seq' || 'At' || 'Speed' || 'Repeat':
        refuse(
          e.offset,
          'arguments',
          '$name takes ${name == 'Par' || name == 'Seq' ? 'one list' : 'two arguments'}',
        );
        return null;
      default:
        refuse(
          e.offset,
          'unknown combinator',
          '"$name" is not an arrangement — Par, Seq, At, Speed or Repeat',
        );
        return null;
    }
  }

  (String, ArgumentList)? _invocation(Expression e) => switch (e) {
    MethodInvocation(:var methodName, :var target, :var argumentList)
        when target == null =>
      (methodName.name, argumentList),
    InstanceCreationExpression(:var constructorName, :var argumentList)
        when constructorName.name == null =>
      (constructorName.type.name.lexeme, argumentList),
    _ => null,
  };

  double? _double(Expression e) {
    var negate = false;
    var inner = e;
    if (inner is PrefixExpression && inner.operator.lexeme == '-') {
      negate = true;
      inner = inner.operand;
    }
    var value = switch (inner) {
      IntegerLiteral(:var value) => value?.toDouble(),
      DoubleLiteral(:var value) => value,
      _ => null,
    };
    if (value == null) {
      refuse(e.offset, _kind(e), 'expected a number literal');
      return null;
    }
    return negate ? -value : value;
  }

  SceneColor? _colorOf(Expression e) {
    if (_invocation(e) case ('Color', var args)
        when args.arguments.length == 1) {
      var v = args.arguments.single.argumentExpression;
      if (v is IntegerLiteral && v.value != null) return SceneColor(v.value!);
    }
    refuse(e.offset, _kind(e), 'expected a color, spelled Color(0xAARRGGBB)');
    return null;
  }

  String _kind(Expression e) => switch (e) {
    ConditionalExpression() => 'conditional',
    BinaryExpression() => 'arithmetic',
    MethodInvocation() => 'method call',
    StringInterpolation() => 'interpolation',
    AdjacentStrings() => 'adjacent strings',
    SimpleIdentifier() => 'identifier',
    PrefixedIdentifier() => 'identifier',
    _ => e.runtimeType.toString(),
  };
}
