import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class FittedApp extends StatefulWidget {
  final Widget child;
  final Size minimumSize;

  const FittedApp({super.key, required this.child, required this.minimumSize});

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
    var widthRatio = size.width / widget.minimumSize.width;
    var heightRatio = size.height / widget.minimumSize.height;

    var width = size.width;
    var height = size.height;

    if (min(widthRatio, heightRatio) < 1) {
      if (widthRatio < heightRatio) {
        width = widget.minimumSize.width;
        height = size.height / widthRatio;
      } else {
        height = widget.minimumSize.height;
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
