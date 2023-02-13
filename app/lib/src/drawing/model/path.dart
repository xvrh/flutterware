import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/src/dart/ast/token.dart'; //ignore: implementation_imports
import 'package:flutter/foundation.dart';
import 'package:flutterware_app/src/drawing/model/property_bag_parser.dart';
import 'package:flutterware_app/src/drawing/model/utils.dart';
import 'package:flutterware/drawing.dart';
import 'file.dart';
import 'mockup.dart';

class DrawingPath with ChangeNotifier implements DrawingEntry {
  @override
  final String name;
  final _entries = <PathEntry>[];
  final _mockups = <MockupElement>[];
  PaintPreview? _preview;

  DrawingPath(this.name);

  static DrawingPath? fromCode(TopLevelVariableDeclaration declaration) {
    var variable = declaration.variables.variables.first;
    var initializer = variable.initializer;

    var result = DrawingPath(variable.name.value().toString());
    if (initializer is MethodInvocation &&
        initializer.methodName.name == 'PathBuilder') {
      var elements = initializer.argumentList.arguments.first as ListLiteral;
      for (var element in elements.elements.cast<MethodInvocation>()) {
        if (element.methodName.name == 'MoveTo') {
          result._entries.add(MoveToEntry.fromCode(element));
        } else if (element.methodName.name == 'LineTo') {
          result._entries.add(LineToEntry.fromCode(element));
        } else if (element.methodName.name == 'Close') {
          result._entries.add(CloseEntry());
        }
      }
      var comments = _readAllComments(declaration.beginToken);
      for (var comment in comments) {
        if (comment.name == 'mockup') {
          result._mockups.add(MockupElement.fromCode(comment.values));
        } else if (comment.name == 'preview') {
        result._preview = PaintPreview.fromCode(comment.values);
        }
      }

      return result;
    }

    return null;
  }

  @override
  String get typeName => 'Path';

  Iterable<PathEntry> get entries => _entries;

  static List<PropertyBag> _readAllComments(Token beginToken) {
    var results = <PropertyBag>[];
    Token? commentToken = beginToken.precedingComments;
    while (commentToken != null && commentToken is CommentToken) {
      var rawComment = commentValue(commentToken.value());
      results.add(PropertyBag.parse(rawComment));

      commentToken = commentToken.next;
    }

    return results;
  }

  @override
  String toCode() {
    var code = StringBuffer();
    for (var mockup in _mockups) {
      code.writeln('// ${mockup.toCodeComment()}');
    }
    var preview = _preview;
    if (preview != null) {
      code.writeln('// ${preview.toCodeComment()}');
    }
    code.writeln('final $name = PathBuilder([');
    for (var entry in _entries) {
      code.writeln('${entry.toCode()},');
    }
    code.writeln(']);');
    return '$code';
  }

  PathBuilder toPath() {
    var builder = PathBuilder([
      for (var entry in _entries)
        entry.toRuntime(),
    ]);
    return builder;
  }

  @override
  void dispose() {
    for (var entry in _entries) {
      entry.dispose();
    }
    for (var mockup in _mockups) {
      mockup.dispose();
    }
    _preview?.dispose();

    super.dispose();
  }
}

class PaintPreview {
  final stroke = ValueNotifier<double>(2);

  PaintPreview();

  factory PaintPreview.fromCode(Map<String, dynamic> values) {
    var element = PaintPreview()
      ..stroke.value = (values['stroke'] as num?)?.toDouble() ?? 0;

    return element;
  }

  String toCodeComment() {
    return PropertyBag('preview', {
      'stroke': stroke.value,
    }).toString();
  }

  void dispose() {
    stroke.dispose();
  }
}

abstract class PathEntry implements ChangeNotifier {
  String toCode();
  PathCommand toRuntime();
}

class MoveToEntry with ChangeNotifier implements PathEntry {
  double _x = 0;
  double _y = 0;

  MoveToEntry();

  factory MoveToEntry.fromCode(MethodInvocation invocation) {
    var arguments = invocation.argumentList.arguments;

    return MoveToEntry()
      .._x = expressionToDouble(arguments[0])
      .._y = expressionToDouble(arguments[1]);
  }

  double get x => _x;
  set x(double x) {
    if (x != _x) {
      _x = x;
      notifyListeners();
    }
  }

  double get y => _y;
  set y(double y) {
    if (y != _y) {
      _y = y;
      notifyListeners();
    }
  }

  @override
  String toCode() =>
      'MoveTo(${numToCode(_x)}, ${numToCode(_y)})';

  @override
  PathCommand toRuntime() => MoveTo(_x, _y);
}

class LineToEntry with ChangeNotifier implements PathEntry {
  double _x = 0;
  double _y = 0;

  LineToEntry();

  factory LineToEntry.fromCode(MethodInvocation invocation) {
    var arguments = invocation.argumentList.arguments;

    return LineToEntry()
      .._x = expressionToDouble(arguments[0])
      .._y = expressionToDouble(arguments[1]);
  }

  double get x => _x;
  set x(double x) {
    if (x != _x) {
      _x = x;
      notifyListeners();
    }
  }

  double get y => _y;
  set y(double y) {
    if (y != _y) {
      _y = y;
      notifyListeners();
    }
  }

  @override
  String toCode() => 'LineTo(${numToCode(x)}, ${numToCode(y)})';

  @override
  PathCommand toRuntime() => LineTo(x, y);
}

class CloseEntry with ChangeNotifier implements PathEntry {
  @override
  String toCode() => 'Close()';

  @override
  PathCommand toRuntime() => Close();
}
