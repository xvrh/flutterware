import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/file.dart';
import 'package:flutterware_app/src/drawing/model/path.dart';
import 'package:flutterware_app/src/drawing/path_command_editor.dart';
import 'package:path_drawing/path_drawing.dart';

import '../project.dart';

class PathScreen extends StatelessWidget {
  final Project project;
  final DrawingFile file;
  final DrawingPath path;

  const PathScreen(this.project, this.file, this.path, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: path,
      builder: (context, child) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Editor(path)),
            _SidePanel(path),
          ],
        );
      },
    );
  }
}

class _Editor extends StatelessWidget {
  final DrawingPath path;
  const _Editor(this.path);

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      boundaryMargin: EdgeInsets.zero,
      minScale: 0.2,
      maxScale: 10,
      constrained: false,
      child: _Path(path),
    );
  }
}

class _Path extends StatelessWidget {
  final DrawingPath path;
  const _Path(this.path);

  @override
  Widget build(BuildContext context) {
    var uiPath = path.toPath().build();
    var offset = Offset(1000, 1000);
    uiPath = uiPath.shift(offset);

    return SizedBox(
      width: 3000,
      height: 3000,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _Painter(path, uiPath, zeroOffset: offset),
            ),
          ),
          for (var entry in path.entries)
            AnimatedBuilder(
              animation: entry,
              builder: (context, child) {
                if (entry is LineToEntry) {
                  return LineToEditor(entry, offset: offset);
                } else if (entry is MoveToEntry) {
                  return MoveToEditor(entry, offset: offset);
                } else if (entry is CloseEntry) {
                  return const SizedBox();
                } else {
                  throw StateError('Unknown entry ${entry.runtimeType}');
                }
              },
            ),
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  final DrawingPath path;
  const _SidePanel(this.path);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Colors.white,
      child: ListView(
        children: [
          for (var entry in path.entries)
            ListTile(
              title: Text(entry.toCode()),
            )
        ],
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final DrawingPath drawing;
  final Path path;
  final Offset zeroOffset;

  _Painter(this.drawing, this.path, {required this.zeroOffset});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.lightBlue;

    canvas.drawPath(path, paint);

    var referencePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black12;

    var dash = CircularIntervalList<double>([10.0, 5]);
    void drawDashLine(Offset start, Offset end) {
      canvas.drawPath(
          dashPath(
              Path()
                ..moveTo(start.dx, start.dy)
                ..lineTo(end.dx, end.dy),
              dashArray: dash),
          referencePaint);
    }

    drawDashLine(zeroOffset, Offset(size.width, zeroOffset.dy));
    drawDashLine(zeroOffset, Offset(zeroOffset.dx, size.height));

    var paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 12))
      ..pushStyle(ui.TextStyle(color: Colors.black38))
      ..addText('0, 0');
    var paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: 100));
    canvas.drawParagraph(paragraph, Offset(0, -20) + zeroOffset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
