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

    //TODO(xha): improve to keep the aspect ratio
    return FittedBox(
      child: SizedBox(
        width: max(size.width, 450),
        height: max(size.height, 200),
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
