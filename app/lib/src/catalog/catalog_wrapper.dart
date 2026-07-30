import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'catalog_entry.dart';

/// Writes the one file that stands between a demo and whoever renders it: the
/// annotation evaluated as Dart, and the demo's builder, reachable by name.
///
/// Shared by the guest's entrypoint and by the web build, and it has to be
/// shared rather than merely similar. What is encoded here is the demo's own
/// *scope* — which imports were in it, what a relative URI resolves against,
/// why the file is imported twice — and a second copy of those rules would go
/// out of date silently: the symptom is a demo that renders in the panel and
/// not on the page, or the reverse.
class CatalogWrapperWriter {
  CatalogWrapperWriter({required this.outputDir, required this.projectRoot});

  /// Where the wrapper is written. Relative URIs inside it resolve from here.
  final String outputDir;

  /// Resolves each entry's [CatalogEntry.path].
  final String projectRoot;

  /// The source of `entry_<index>.dart` for [entry].
  String source(CatalogEntry entry, int index) {
    var demo = p.join(projectRoot, entry.path);
    // The demo's own imports, and only the demo's. A shell used to contribute
    // its imports too, because the generated call named an axis's enum by type
    // and that type is in scope where the shell is written rather than where
    // the demo is. Axes are declared inside the shell now, so nothing the shell
    // knows about has to be nameable from here — which is what removes the one
    // case where two files' import sets were merged and could collide.
    var carried = carriedImports(demo);
    return '''
// GENERATED — do not edit.
// Imports carried from the demo file: the annotation is written in *its* scope,
// so anything the annotation names has to resolve here too.
${carried.join('\n')}
// Unconditional: the getters below are typed, and a demo file is not obliged
// to import widgets itself.
import 'package:flutter/widgets.dart';
import 'package:flutterware/ui_catalog.dart';

// The demo file twice, and both are load-bearing. Prefixed, because fwBuilder
// has to name the entry unambiguously. Unprefixed, because the annotation may
// name something the demo file *declares* rather than imports — a wrapper
// written beside the demo it wraps is the ordinary case — and a file does not
// import itself, so nothing else would put that in scope.
//
// Together these reproduce the demo's own scope, which is the one the
// annotation was written in. The gap that remains is privacy: a `_kName` in the
// annotation is visible where it was written and not here.
import '${relative(demo)}';
import '${relative(demo)}' as fw$index;

// The annotation, evaluated as Dart rather than interpreted statically.
// `transform()` returns a plain Preview and drops id/figma/formFactor, so the
// annotation itself is kept alongside it.
//
// Getters, not consts. A const holding a function tear-off — every `wrapper:`
// is one — is inlined into whichever library reads it, so the entrypoint's
// constant pool ends up referring to a procedure in the demo's own file. A
// reload that carries only the entrypoint then has to re-resolve that
// reference against a library it does not contain, and the guest renders
// `Lookup failed: <wrapper> in @methods in file:...` instead of the demo.
// Behind a getter there is nothing to inline and nothing to re-resolve.
Demo get fwDemo => ${entry.annotation};

Widget Function() get fwBuilder => fw$index.${entry.symbol};
''';
  }

  /// The demo file's own import and export directives, with relative URIs
  /// rewritten to resolve from [outputDir].
  ///
  /// Demo files live outside `lib/` and so have no `package:` URI of their own;
  /// a carried `../utils/shell.dart` would not resolve from the generated
  /// directory without this.
  ///
  /// Parsed rather than matched. The regex this replaced was line-oriented, so
  /// a directive written across two lines — which `dart format` produces as
  /// soon as a `show` clause makes it long enough — was carried as a fragment
  /// or dropped. Everything a directive can carry (`show`, `hide`, `as`,
  /// `deferred`, configurable imports) is kept here by rewriting only the URI
  /// literals inside the directive's own source and leaving the rest alone.
  /// `part` is deliberately not carried: a part belongs to its own library.
  List<String> carriedImports(String source) {
    var unit = parseString(
      content: File(source).readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit;

    var carried = <String>[];
    for (var directive in unit.directives) {
      if (directive is! NamespaceDirective) continue;
      var uri = directive.uri.stringValue;
      // `package:flutterware/ui_catalog.dart` is emitted unconditionally below.
      if (uri == null || uri == 'package:flutterware/ui_catalog.dart') continue;

      var text = directive.toSource();
      for (var literal in [
        directive.uri,
        for (var configuration in directive.configurations) configuration.uri,
      ]) {
        var written = literal.stringValue;
        // A `package:`/`dart:` URI means the same thing from anywhere.
        if (written == null || written.contains(':')) continue;
        var target = p.normalize(p.join(p.dirname(source), written));
        text = text.replaceFirst(literal.toSource(), "'${relative(target)}'");
      }
      carried.add(text);
    }
    return carried;
  }

  /// Always `/`-separated: this ends up inside a URI literal, where a Windows
  /// separator is an escape rather than a path.
  String relative(String target) =>
      p.split(p.relative(target, from: outputDir)).join('/');
}
