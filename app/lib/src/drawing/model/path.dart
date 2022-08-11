import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/src/dart/ast/token.dart'; //ignore: implementation_imports
import 'package:flutter/foundation.dart';
import 'package:flutterware_app/src/drawing/model/property_bag_parser.dart';
import 'package:flutterware_app/src/drawing/model/utils.dart';

import 'file.dart';
import 'mockup.dart';

var _globalId = 0;

class PathElement with ChangeNotifier implements DrawingEntry {
  final ValueNotifier<String> _name;
  final _commands = <PathCommand>[];
  final _mockups = <MockupElement>[];
  PaintPreview? _preview;

  PathElement(String name) : _name = ValueNotifier<String>(name);

  static PathElement? fromCode(TopLevelVariableDeclaration declaration) {
    var variable = declaration.variables.variables.first;
    var initializer = variable.initializer;

    var result = PathElement(variable.name.name);
    if (initializer is MethodInvocation &&
        initializer.methodName.name == 'PathBuilder') {
      var elements = initializer.argumentList.arguments.first as ListLiteral;
      for (var element in elements.elements.cast<MethodInvocation>()) {
        if (element.methodName.name == 'MoveTo') {
          result._commands.add(MoveToCommand.fromCode(element));
        } else if (element.methodName.name == 'LineTo') {
          result._commands.add(LineToCommand.fromCode(element));
        } else if (element.methodName.name == 'Close') {
          result._commands.add(CloseCommand());
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
  final String id = '${++_globalId}';

  @override
  ValueListenable<String> get name => _name;

  @override
  String get typeName => 'Path';

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
    code.writeln('final ${_name.value} = PathBuilder([');
    for (var command in _commands) {
      code.writeln('${command.toCode()},');
    }
    code.writeln(']);');
    return '$code';
  }

  @override
  void dispose() {
    _name.dispose();
    for (var command in _commands) {
      command.dispose();
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

abstract class PathCommand implements ChangeNotifier {
  String toCode();
}

class MoveToCommand with ChangeNotifier implements PathCommand {
  final x = ValueNotifier<double>(0);
  final y = ValueNotifier<double>(0);

  MoveToCommand() {
    x.addListener(notifyListeners);
    y.addListener(notifyListeners);
  }

  factory MoveToCommand.fromCode(MethodInvocation invocation) {
    var arguments = invocation.argumentList.arguments;

    return MoveToCommand()
      ..x.value = expressionToDouble(arguments[0])
      ..y.value = expressionToDouble(arguments[1]);
  }

  @override
  String toCode() =>
      'MoveTo(${numToCode(x.value)}, ${numToCode(y.value)})';

  @override
  void dispose() {
    x.dispose();
    y.dispose();

    super.dispose();
  }
}

class LineToCommand with ChangeNotifier implements PathCommand {
  final x = ValueNotifier<double>(0);
  final y = ValueNotifier<double>(0);

  LineToCommand() {
    x.addListener(notifyListeners);
    y.addListener(notifyListeners);
  }

  factory LineToCommand.fromCode(MethodInvocation invocation) {
    var arguments = invocation.argumentList.arguments;

    return LineToCommand()
      ..x.value = expressionToDouble(arguments[0])
      ..y.value = expressionToDouble(arguments[1]);
  }

  @override
  String toCode() => 'LineTo(${numToCode(x.value)}, ${numToCode(y.value)})';

  @override
  void dispose() {
    x.dispose();
    y.dispose();

    super.dispose();
  }
}

class CloseCommand with ChangeNotifier implements PathCommand {
  @override
  String toCode() => 'Close()';
}
