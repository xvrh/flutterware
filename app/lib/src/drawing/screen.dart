

import 'package:flutter/material.dart';
import 'package:flutterware_app/src/utils.dart';

import 'board.dart';

class DrawingScreen extends StatelessWidget {
  const DrawingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RouterOutlet({'file/:file': (r) => BoardScreen()});
  }
}
