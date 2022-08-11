import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/path.dart';

class PointHandle extends StatelessWidget {
  final double x, y;

  const PointHandle({super.key, required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    const pointWidth = 10.0;

    return Positioned(
      left: x - pointWidth / 2,
      top: y - pointWidth / 2,
      child: InkWell(
        onTap: () {
          print("Tap");
        },
        child: Container(
          width: pointWidth,
          height: pointWidth,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(width: 3, color: Colors.blueAccent),
          ),
        ),
      ),
    );
  }
}

class LineToEditor extends StatelessWidget {
  final LineToEntry entry;

  const LineToEditor(this.entry, {super.key});

  @override
  Widget build(BuildContext context) {
    return PointHandle(
      x: entry.x,
      y: entry.y,
    );
  }
}

class MoveToEditor extends StatelessWidget {
  final MoveToEntry entry;

  const MoveToEditor(this.entry, {super.key});

  @override
  Widget build(BuildContext context) {
    return PointHandle(
      x: entry.x,
      y: entry.y,
    );
  }
}
