import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

class PackageImports {
  final Map<String, List<File>> importsForPackage;

  PackageImports(this.importsForPackage);

  List<File> operator [](String packageName) =>
      importsForPackage[packageName] ?? const [];

  static PackageImports gather(Iterable<File> dartFiles) {
    var results = <String, List<File>>{};
    for (var file in dartFiles) {
      var result = parseString(
          content: file.readAsStringSync(),
          path: file.path,
          throwIfDiagnostics: false);
      if (result.errors.isEmpty) {
        for (var directive in result.unit.directives) {
          if (directive is NamespaceDirective) {
            var uriContent = directive.uri.stringValue;
            if (uriContent != null && uriContent.startsWith('package:')) {
              var uri = Uri.tryParse(uriContent);
              if (uri != null) {
                var packageName = uri.pathSegments.first;
                var files = results[packageName] ??= [];
                files.add(file);
              }
            }
          }
        }
      }
    }
    return PackageImports(results);
  }
}
