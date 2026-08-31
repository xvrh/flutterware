// Disposable spike: run the SDK-mining extractor's logic over a *user*
// package's widgets, to measure what a syntactic scan gives external-widget
// registration for free — and what a registration must still supply by hand.
//
// Run: cd app && fvm dart tool/user_widget_probe.dart
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

void main(List<String> args) {
  var root = Directory('../examples/example/lib');
  var units = <String, CompilationUnit>{};
  for (var file
      in root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
    units[file.path] = parseString(
      content: file.readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit;
  }
  stderr.writeln('parsed ${units.length} files');

  var enums = <String>{
    'TextAlign',
    'TextDirection',
    'FontWeight',
    'FontStyle',
    'Clip',
    'Brightness',
    'TextOverflow',
    'BoxFit',
    'Axis',
    'MainAxisAlignment',
    'CrossAxisAlignment',
    'MainAxisSize',
  };
  var superOf = <String, String>{};
  var classDecls = <String, ClassDeclaration>{};
  var classFile = <String, String>{};

  for (var entry in units.entries) {
    for (var decl in entry.value.declarations) {
      if (decl is EnumDeclaration) enums.add(decl.namePart.typeName.lexeme);
      if (decl is ClassDeclaration) {
        var name = decl.namePart.typeName.lexeme;
        classDecls[name] = decl;
        classFile[name] = entry.key;
        var sup = decl.extendsClause?.superclass.name.lexeme;
        if (sup != null) superOf[name] = sup;
      }
    }
  }

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
    'EdgeInsets',
    'EdgeInsetsGeometry',
    'Alignment',
    'AlignmentGeometry',
    'BorderRadius',
    'TextStyle',
    'Curve',
    'IconData',
    'ImageProvider',
    'Locale',
  };

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
        base == 'ValueChanged') {
      return 'callback';
    }
    return 'other';
  }

  for (var probe in [
    'MiniMarkdown',
    'DrinkBadge',
    'DrinkScreen',
    'WelcomeScreen',
    'DashboardTile',
  ]) {
    var decl = classDecls[probe];
    if (decl == null) {
      print('== $probe: NOT FOUND');
      continue;
    }
    var ctor = decl.body.members
        .whereType<ConstructorDeclaration>()
        .where((c) => c.name == null || c.name!.lexeme == 'new')
        .firstOrNull;
    print('== $probe  (${classFile[probe]!.split('/lib/').last})');
    print(
      '   doc: ${decl.documentationComment != null ? 'yes' : 'no'}'
      '  superclass: ${superOf[probe]}',
    );
    if (ctor == null) {
      print('   no public unnamed constructor');
      continue;
    }
    var owed = <String>[];
    var tunable = <String>[];
    for (var p in ctor.parameters.parameters) {
      var pname = p.name?.lexeme ?? '?';
      var type = p.type?.toSource() ?? fieldType(probe, pname);
      var kind = classify(type);
      if (kind == 'key') continue;
      var dflt = p.defaultClause?.value.toSource();
      var required = p.isRequired || (p.isPositional && dflt == null);
      print(
        '   ${p.isNamed ? 'named' : 'positional'} $pname: $type'
        '  [$kind]${required ? ' required' : ''}'
        '${dflt != null ? '  = $dflt' : ''}',
      );
      var representable = const {'scalar', 'enum', 'child'}.contains(kind);
      if (representable) {
        tunable.add(pname);
      } else if (required) {
        owed.add(pname);
      }
    }
    print('   -> editor-tunable: $tunable');
    print('   -> registration owes: ${owed.isEmpty ? 'nothing' : owed}');

    // Context requirements: `.of(context)` calls in the widget's own file,
    // inside this class (and its State class for a StatefulWidget) — a
    // syntactic warning surface, not a provision mechanism.
    var contextNeeds = <String>{};
    void scanClass(ClassDeclaration c) {
      var source = c.toSource();
      for (var m in RegExp(
        r'([A-Z][A-Za-z0-9_]*)\.of\(context\)',
      ).allMatches(source)) {
        contextNeeds.add(m.group(1)!);
      }
    }

    scanClass(decl);
    var state = classDecls['_${probe}State'] ?? classDecls['${probe}State'];
    if (state != null) scanClass(state);
    print(
      '   -> needs from context: ${contextNeeds.isEmpty ? 'nothing detected' : contextNeeds.toList()}',
    );
    print('');
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
