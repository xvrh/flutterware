import 'package:flutter/foundation.dart';
import 'package:flutterware_app/src/drawing/model/property_bag_parser.dart';

class MockupElement {
  final path = ValueNotifier<String>('');
  final x = ValueNotifier<double>(0);
  final y = ValueNotifier<double>(0);
  final width = ValueNotifier<double>(100);
  final height = ValueNotifier<double>(100);
  final opacity = ValueNotifier<double>(1);

  MockupElement();

  factory MockupElement.fromCode(Map<String, dynamic> values) {
    var element = MockupElement()
      ..path.value = values['path'] as String? ?? ''
      ..x.value = (values['x'] as num?)?.toDouble() ?? 0
      ..y.value = (values['y'] as num?)?.toDouble() ?? 0
      ..width.value = (values['w'] as num?)?.toDouble() ?? 100
      ..height.value = (values['h'] as num?)?.toDouble() ?? 100
      ..opacity.value = (values['opacity'] as num?)?.toDouble() ?? 1;

    return element;
  }

  String toCodeComment() {
    var bag = PropertyBag('mockup', {
      'path': path.value,
      'x': x.value,
      'y': y.value,
      'w': width.value,
      'h': height.value,
      if (opacity.value < 1) 'opacity': opacity.value,
    });
    return bag.toString();
  }

  void dispose() {
    path.dispose();
    x.dispose();
    y.dispose();
    width.dispose();
    height.dispose();
  }
}
