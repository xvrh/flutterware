

import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter/foundation.dart';

import 'mockup.dart';

class PathElement {
  final _commands = <PathCommand>[];
  final _mockups = <MockupElement>[];

  factory PathElement(TopLevelVariableDeclaration declaration) {

  }

  String toCode() {
    var code = StringBuffer();

    return '$code';
  }
}

abstract class PathPreview {
  String toComment();
}

abstract class PathCommand implements Listenable {}

class MoveCommand with ChangeNotifier {
  final x = ValueNotifier<num>(0);
  final y = ValueNotifier<num>(0);

  MoveCommand() {
    x.addListener(notifyListeners);
    y.addListener(notifyListeners);
  }

  @override
  void dispose() {
    x.dispose();
    y.dispose();

    super.dispose();
  }
}