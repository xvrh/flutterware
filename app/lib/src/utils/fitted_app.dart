import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class FittedApp extends StatefulWidget {
  final Widget child;

  const FittedApp({super.key, required this.child});

  @override
  State<FittedApp> createState() => _FittedAppState();
}

class _FittedAppState extends State<FittedApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    setState(() {
      // rebuild
    });
  }

  @override
  Widget build(BuildContext context) {
    var size = window.physicalSize / window.devicePixelRatio;

    const minWidth = 450.0;
    const minHeight = 400.0;

    var widthRatio = size.width / minWidth;
    var heightRatio = size.height / minHeight;

    var width = size.width;
    var height = size.height;

    if (min(widthRatio, heightRatio) < 1) {
      if (widthRatio < heightRatio) {
        width = minWidth;
        height = size.height / widthRatio;
      } else {
        height = minHeight;
        width = size.width / heightRatio;
      }
    }

    return FittedBox(
      child: SizedBox(
        width: width,
        height: height,
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }
}
