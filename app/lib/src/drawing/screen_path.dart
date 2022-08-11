import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/file.dart';
import 'package:flutterware_app/src/drawing/model/path.dart';
import 'package:flutterware_app/src/drawing/path_command_editor.dart';
import 'package:more/math.dart';

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
      boundaryMargin:
          const EdgeInsets.only(left: 500, top: 500, bottom: 1000, right: 1000),
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
    var bounds = uiPath.getBounds().inflate(20);
    //uiPath = uiPath.shift(Offset(-bounds.left, -bounds.top));

    return Container(
      //color: Colors.green.withOpacity(0.2),
      clipBehavior: Clip.none,
      child: SizedBox(
        width: 1500,
        height: 1500,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.blue.withOpacity(0.05),
                child: CustomPaint(
                  painter: _Painter(path, uiPath),
                ),
              ),
            ),
            Positioned.fill(
              left: -bounds.left,
              top: -bounds.top,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var entry in path.entries)
                    AnimatedBuilder(
                      animation: entry,
                      builder: (context, child) {
                        if (entry is LineToEntry) {
                          return LineToEditor(entry);
                        } else if (entry is MoveToEntry) {
                          return MoveToEditor(entry);
                        } else if (entry is CloseEntry) {
                          return const SizedBox();
                        } else {
                          throw StateError(
                              'Unknown entry ${entry.runtimeType}');
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
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

  _Painter(this.drawing, this.path);

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.lightBlue;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
