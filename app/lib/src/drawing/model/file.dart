

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:logging/logging.dart';
import 'package:dart_style/dart_style.dart';

import 'path.dart';

final _formatter = DartFormatter();

class DrawingFile {
  static final fileTag = '//@flutterware:drawing=1.0';
  static const fileExtension = '.gen.dart';

  final String filePath;
  final _paths = <PathElement>[];

  DrawingFile(this.filePath);

  static DrawingFile parse(String filePath, String source) {
    var result = parseString(content: source);
    var unit = result.unit;

    var file = DrawingFile(filePath);
    for (var topLevelVariable in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      var path = PathElement.fromCode(topLevelVariable);
      if (path != null) {
        file._paths.add(path);
      }
    }

    return file;
  }

  String toCode() {
    var buffer = StringBuffer('''
$fileTag
import 'package:flutterware/drawing.dart';
''');

    for (var path in _paths) {
      buffer.writeln(path.toCode());
    }

    return _formatter.format('$buffer');
  }

  void dispose() {
    for (var path in _paths) {
      path.dispose();
    }
  }
}