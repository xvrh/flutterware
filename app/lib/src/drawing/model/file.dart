import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_style/dart_style.dart';
import 'package:flutter/foundation.dart';
import 'package:pub_semver/pub_semver.dart';
import 'path.dart';

final _formatter = DartFormatter(languageVersion: Version(3, 5, 0));

class DrawingFile {
  static final fileTag = '//@flutterware:drawing=1.0';
  static const fileExtension = '.gen.dart';

  final String filePath;
  final _entries = ValueNotifier<List<DrawingEntry>>([]);

  DrawingFile(this.filePath);

  static DrawingFile parse(String filePath, String source) {
    var result = parseString(content: source);
    var unit = result.unit;

    var file = DrawingFile(filePath);

    var entries = <DrawingEntry>[];

    for (var topLevelVariable
        in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      var path = DrawingPath.fromCode(topLevelVariable);
      if (path != null) {
        entries.add(path);
      }
    }
    file._entries.value = entries;

    return file;
  }

  ValueListenable<List<DrawingEntry>> get entries => _entries;

  String toCode() {
    var buffer = StringBuffer('''
$fileTag
import 'package:flutterware/drawing.dart';
''');

    for (var path in _entries.value) {
      buffer.writeln(path.toCode());
    }

    return _formatter.format('$buffer');
  }

  void dispose() {
    for (var path in _entries.value) {
      path.dispose();
    }
    _entries.dispose();
  }
}

abstract class DrawingEntry {
  String get name;
  String get typeName;
  String toCode();
  void dispose();
}
