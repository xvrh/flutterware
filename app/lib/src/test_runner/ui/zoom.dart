import 'dart:math';
import 'package:flutter/material.dart';

class ZoomButtons extends StatelessWidget {
  final double value;
  final void Function(double) onScale;

  const ZoomButtons({super.key, required this.value, required this.onScale});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          _button(Icons.zoom_out, () {
            onScale(0.9);
          }),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(fontSize: 12),
          ),
          _button(Icons.zoom_in, () {
            onScale(1.1);
          }),
        ],
      ),
    );
  }

  Widget _button(IconData icon, void Function() onPressed) {
    return TextButton(
      onPressed: onPressed,
      style:
          TextButton.styleFrom(primary: Colors.black45, minimumSize: Size.zero),
      child: Icon(
        icon,
        size: 20,
      ),
    );
  }
}
