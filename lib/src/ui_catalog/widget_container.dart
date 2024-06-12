import 'package:flutter/material.dart';

class WidgetContainer extends StatelessWidget {
  final Widget child;
  final bool enableDeviceFrame;

  const WidgetContainer({
    super.key,
    required this.child,
    this.enableDeviceFrame = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
