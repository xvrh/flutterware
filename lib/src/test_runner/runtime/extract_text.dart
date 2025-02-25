import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' show MatchFinder;
import '../protocol/models.dart';

TextInfo textInfoFromElement(String translationKey, Element element,
    {required String rawTranslation}) {
  var box = element.renderObject! as RenderBox;
  var topLeft = box.localToGlobal(Offset.zero);
  var bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));

  var style = styleFromElement(element);

  var text = textFromElement(element)!;

  return TextInfo(
          text: text,
          translationKey: translationKey,
          rawTranslation: rawTranslation,
          globalRectangle: Rectangle.fromLTRB(
              topLeft.dx, topLeft.dy, bottomRight.dx, bottomRight.dy))
      .rebuild((b) => b
        ..color = style.color?.toARGB32()
        ..fontSize = style.fontSize
        ..fontFamily = style.fontFamily
        ..fontWeight = style.fontWeight?.index);
}

String? textFromElement(Element candidate) {
  final widget = candidate.widget;
  if (widget is Text) {
    var data = widget.data;
    if (data != null) {
      return data;
    } else {
      return widget.textSpan!.toPlainText();
    }
  } else if (widget is EditableText) {
    return widget.controller.text;
  }
  //TODO(xha): add a plugin system to be able to detect markdown (without markdown dependency)

  return null;
}

TextStyle styleFromElement(Element candidate) {
  final widget = candidate.widget;
  TextStyle? style;

  //TODO(xha): support rich text?
  if (widget is Text) {
    style = widget.style;
  } else if (widget is EditableText) {
    style = widget.style;
  }
  var defaultStyle = DefaultTextStyle.of(candidate).style;
  if (style != null) {
    return defaultStyle.merge(style);
  }

  return defaultStyle;
}

class TextFinder extends MatchFinder {
  TextFinder(this.text, {super.skipOffstage});

  final String text;

  @override
  String get description => 'text "$text"';

  @override
  bool matches(Element candidate) {
    var found = textFromElement(candidate);
    return found == text;
  }
}
