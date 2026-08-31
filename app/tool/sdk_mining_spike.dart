// Disposable spike: mine the pinned Flutter SDK's sources for widget
// constructor schemas, syntactically (parse, never resolve). Answers: if we
// generated the editor catalog from the SDK, what coverage would we get?
//
// Run: cd app && fvm dart tool/sdk_mining_spike.dart
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> args) {
  var home = Platform.environment['HOME']!;
  var sdk = Directory(
    '$home/fvm/versions/3.48.0-0.2.pre/packages/flutter/lib/src',
  );
  if (!sdk.existsSync()) {
    stderr.writeln('SDK not found at ${sdk.path}');
    exit(1);
  }

  var libraries = ['widgets', 'material', 'cupertino'];
  var units = <String, CompilationUnit>{};
  for (var lib in libraries) {
    for (var file
        in Directory('${sdk.path}/$lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      var result = parseString(
        content: file.readAsStringSync(),
        throwIfDiagnostics: false,
      );
      units[file.path] = result.unit;
    }
  }
  stderr.writeln('parsed ${units.length} files');

  // Pass 1: enums declared anywhere in the corpus, plus known dart:ui enums.
  var enums = <String>{
    'TextAlign',
    'TextDirection',
    'TextBaseline',
    'FontStyle',
    'FontWeight',
    'Clip',
    'BlendMode',
    'FilterQuality',
    'StrokeCap',
    'StrokeJoin',
    'PaintingStyle',
    'TileMode',
    'BoxHeightStyle',
    'BoxWidthStyle',
    'Brightness',
    'TextOverflow',
    'TextWidthBasis',
    'TargetPlatform',
    'TextLeadingDistribution',
  };
  var superOf = <String, String>{};
  var classDecls = <String, ClassDeclaration>{};

  // Enum pass covers the whole SDK: many enums widgets reference live in
  // painting/rendering/gestures/services.
  for (var file
      in sdk
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    if (units.containsKey(file.path)) continue;
    var unit = parseString(
      content: file.readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit;
    for (var decl in unit.declarations) {
      if (decl is EnumDeclaration) enums.add(decl.namePart.typeName.lexeme);
    }
  }

  for (var unit in units.values) {
    for (var decl in unit.declarations) {
      if (decl is EnumDeclaration) enums.add(decl.namePart.typeName.lexeme);
      if (decl is ClassDeclaration) {
        var name = decl.namePart.typeName.lexeme;
        classDecls[name] = decl;
        var sup = decl.extendsClause?.superclass.name.lexeme;
        if (sup != null) superOf[name] = sup;
      }
    }
  }

  const widgetRoots = {
    'StatelessWidget',
    'StatefulWidget',
    'InheritedWidget',
    'ProxyWidget',
    'ParentDataWidget',
    'RenderObjectWidget',
    'SingleChildRenderObjectWidget',
    'MultiChildRenderObjectWidget',
    'LeafRenderObjectWidget',
    'Widget',
  };

  bool isWidget(String className) {
    var seen = <String>{};
    String? cur = className;
    while (cur != null && seen.add(cur)) {
      if (widgetRoots.contains(cur)) return true;
      cur = superOf[cur];
    }
    return false;
  }

  // Type lookup for `this.x` / `super.x` params: walk the class chain.
  String? fieldType(String? className, String field) {
    var seen = <String>{};
    var cur = className;
    while (cur != null && seen.add(cur)) {
      var decl = classDecls[cur];
      if (decl != null) {
        for (var member in decl.body.members) {
          if (member is FieldDeclaration) {
            for (var v in member.fields.variables) {
              if (v.name.lexeme == field) return member.fields.type?.toSource();
            }
          }
          if (member is ConstructorDeclaration) {
            for (var p in member.parameters.parameters) {
              if (p.name?.lexeme == field && p.type != null) {
                return p.type!.toSource();
              }
            }
          }
        }
      }
      cur = superOf[cur];
    }
    return null;
  }

  const scalarTypes = {
    'bool',
    'int',
    'double',
    'num',
    'String',
    'Color',
    'Duration',
    'DateTime',
    'Offset',
    'Size',
    'Rect',
    'Radius',
    'EdgeInsets',
    'EdgeInsetsGeometry',
    'EdgeInsetsDirectional',
    'Alignment',
    'AlignmentGeometry',
    'AlignmentDirectional',
    'BorderRadius',
    'BorderRadiusGeometry',
    'TextStyle',
    'StrutStyle',
    'Curve',
    'IconData',
    'BoxConstraints',
    'Border',
    'BoxBorder',
    'BorderSide',
    'BoxDecoration',
    'Decoration',
    'ShapeBorder',
    'OutlinedBorder',
    'InputBorder',
    'Gradient',
    'BoxShadow',
    'Shadow',
    'ImageProvider',
    'Locale',
    'Matrix4',
    'TextSpan',
    'InlineSpan',
    'VisualDensity',
    'MaterialColor',
    'CupertinoDynamicColor',
    'IconThemeData',
  };

  var otherTypes = <String, int>{};

  String classify(String? rawType) {
    if (rawType == null) return 'untyped';
    var t = rawType.replaceAll('?', '').trim();
    if (t == 'Widget' || t == 'List<Widget>') return 'child';
    if (t == 'Key') return 'key';
    var base = t.contains('<') ? t.substring(0, t.indexOf('<')) : t;
    if (scalarTypes.contains(base)) return 'scalar';
    if (enums.contains(base)) return 'enum';
    if (rawType.contains('Function(') ||
        base == 'VoidCallback' ||
        base.endsWith('Callback') ||
        base.endsWith('Builder') ||
        base == 'ValueChanged' ||
        base == 'ValueSetter' ||
        base == 'ValueGetter' ||
        base.startsWith('GestureTap') ||
        base.startsWith('GestureLongPress') ||
        base.startsWith('GestureDrag')) {
      return 'callback';
    }
    if (base.endsWith('Controller') ||
        base.endsWith('Notifier') ||
        base == 'FocusNode' ||
        base == 'ScrollPhysics' ||
        base == 'Animation' ||
        base == 'Listenable') {
      return 'runtime-object';
    }
    if (base.endsWith('ThemeData') || base.endsWith('Style')) return 'theme';
    return 'other';
  }

  var widgets = <Map<String, dynamic>>[];

  for (var entry in units.entries) {
    var lib = entry.key.contains('/material/')
        ? 'material'
        : entry.key.contains('/cupertino/')
        ? 'cupertino'
        : 'widgets';
    for (var decl in entry.value.declarations) {
      if (decl is! ClassDeclaration) continue;
      var name = decl.namePart.typeName.lexeme;
      if (name.startsWith('_')) continue;
      if (decl.abstractKeyword != null) continue;
      if (!isWidget(name)) continue;

      var ctors = decl.body.members
          .whereType<ConstructorDeclaration>()
          .where((c) => !(c.name?.lexeme.startsWith('_') ?? false))
          .toList();
      if (ctors.isEmpty) continue;
      var ctor =
          ctors
              .where((c) => c.name == null || c.name!.lexeme == 'new')
              .firstOrNull ??
          ctors.first;

      var params = <Map<String, dynamic>>[];
      for (var p in ctor.parameters.parameters) {
        var pname = p.name?.lexeme ?? '?';
        String? type = p.type?.toSource();
        if (type == null && p is FieldFormalParameter) {
          type = fieldType(name, pname);
        } else if (type == null && p is SuperFormalParameter) {
          type = fieldType(superOf[name], pname);
        }
        var kind = classify(type);
        if (kind == 'other' && type != null) {
          var base = type.replaceAll('?', '');
          otherTypes[base] = (otherTypes[base] ?? 0) + 1;
        }
        var dflt = p.defaultClause?.value;
        params.add({
          'name': pname,
          'type': type,
          'kind': kind,
          'required': p.isRequired,
          'hasDefault': dflt != null,
          if (dflt != null)
            'defaultKind': dflt is Literal
                ? 'literal'
                : dflt is InstanceCreationExpression || dflt is MethodInvocation
                ? 'const-ctor'
                : dflt is Identifier
                ? 'identifier'
                : 'expr',
        });
      }

      widgets.add({
        'name': name,
        'library': lib,
        'params': params,
        'doc':
            decl.documentationComment != null ||
            ctor.documentationComment != null,
      });
    }
  }

  // ---- Aggregate ----
  var byLib = <String, int>{};
  var totalParams = 0;
  var byKind = <String, int>{};
  var editableDist = <String, int>{};
  var fullyInstantiable = 0;
  var withDoc = 0;
  var defaultsPresent = 0;
  var defaultsRecoverable = 0;

  for (var w in widgets) {
    byLib[w['library'] as String] = (byLib[w['library'] as String] ?? 0) + 1;
    if (w['doc'] == true) withDoc++;
    var params = (w['params'] as List).cast<Map<String, dynamic>>();
    var nonKey = params.where((p) => p['kind'] != 'key').toList();
    totalParams += nonKey.length;
    for (var p in nonKey) {
      byKind[p['kind'] as String] = (byKind[p['kind'] as String] ?? 0) + 1;
      if (p['hasDefault'] == true) {
        defaultsPresent++;
        if (p['defaultKind'] == 'literal' ||
            p['defaultKind'] == 'const-ctor' ||
            p['defaultKind'] == 'identifier') {
          defaultsRecoverable++;
        }
      }
    }
    var editable = nonKey
        .where((p) => const {'scalar', 'enum', 'child'}.contains(p['kind']))
        .length;
    var pct = nonKey.isEmpty ? 100 : (editable * 100 ~/ nonKey.length);
    var bucket = pct >= 100
        ? '100%'
        : pct >= 75
        ? '75-99%'
        : pct >= 50
        ? '50-74%'
        : pct >= 25
        ? '25-49%'
        : '<25%';
    editableDist[bucket] = (editableDist[bucket] ?? 0) + 1;
    var required = nonKey.where((p) => p['required'] == true);
    if (required.every(
      (p) => const {'scalar', 'enum', 'child'}.contains(p['kind']),
    )) {
      fullyInstantiable++;
    }
  }

  var out = StringBuffer();
  out.writeln('== widgets found: ${widgets.length}  $byLib');
  out.writeln('== with doc comment: $withDoc');
  out.writeln('== non-key constructor params: $totalParams');
  out.writeln(
    '== params with a default: $defaultsPresent (recoverable syntactically: $defaultsRecoverable)',
  );
  out.writeln('== params by kind:');
  var sorted = byKind.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (var e in sorted) {
    out.writeln(
      '   ${e.key.padRight(15)} ${e.value.toString().padLeft(5)}'
      '  ${(e.value * 100 / totalParams).toStringAsFixed(1)}%',
    );
  }
  out.writeln(
    '== editable-share distribution (scalar+enum+child of non-key params):',
  );
  for (var b in ['100%', '75-99%', '50-74%', '25-49%', '<25%']) {
    out.writeln('   ${b.padRight(8)} ${editableDist[b] ?? 0} widgets');
  }
  out.writeln(
    '== instantiable with editor values alone (all required params editable): '
    '$fullyInstantiable / ${widgets.length}',
  );
  out.writeln('== top unclassified ("other") types:');
  var topOther = otherTypes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (var e in topOther.take(25)) {
    out.writeln('   ${e.value.toString().padLeft(3)}  ${e.key}');
  }

  for (var probe in [
    'Container',
    'Text',
    'ElevatedButton',
    'TextField',
    'Row',
    'Stack',
    'Image',
  ]) {
    var w = widgets.where((w) => w['name'] == probe).firstOrNull;
    if (w == null) continue;
    var params = (w['params'] as List).cast<Map<String, dynamic>>();
    var counts = <String, int>{};
    for (var p in params.where((p) => p['kind'] != 'key')) {
      counts[p['kind'] as String] = (counts[p['kind'] as String] ?? 0) + 1;
    }
    out.writeln('== $probe: ${params.length} params  $counts');
  }

  print(out);
  File('${Directory.systemTemp.path}/sdk_mining_widgets.json')
      .writeAsStringSync(jsonEncode(widgets));
  stderr.writeln(
    'detail written to ${Directory.systemTemp.path}/sdk_mining_widgets.json',
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
