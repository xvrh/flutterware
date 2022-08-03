

import 'package:flutter/foundation.dart';

class MockupElement {
  final path = ValueNotifier<String>('');
  final x = ValueNotifier<double>(0);
  final y = ValueNotifier<double>(0);
  final width = ValueNotifier<double>(100);
  final height = ValueNotifier<double>(50);
}