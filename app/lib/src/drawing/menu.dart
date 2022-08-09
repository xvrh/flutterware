import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/file.dart';
import 'package:more/collection.dart';
import 'package:path/path.dart' as p;
import '../project.dart';
import '../ui/side_menu.dart';

class DrawingMenu extends StatelessWidget {
  final Project project;

  const DrawingMenu(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return CollapsibleMenu(
      maintainState: false,
      title: Text('Path & drawing'),
      children: [
        _ListingMenu(project),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {},
          style: OutlinedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 12),
            minimumSize: Size(0, 30),
          ),
          icon: Icon(
            Icons.add,
            size: 12,
          ),
          label: Text('New file'),
        ),
      ],
    );
  }
}

class _ListingMenu extends StatefulWidget {
  final Project project;

  const _ListingMenu(this.project, {super.key});

  @override
  State<_ListingMenu> createState() => __ListingMenuState();
}

class __ListingMenuState extends State<_ListingMenu> {
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    widget.project.drawing.ensureStarted();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Iterable<DrawingFile>>(
      valueListenable: widget.project.drawing.files,
      builder: (context, files, child) {
        return Column(
          children: [
            for (var file
                in files.sortedByCompare((e) => e.filePath, compareNatural))
              MenuLine(
                onTap: () {
                  setState(() {
                    if (_expanded.contains(file.filePath)) {
                      _expanded.remove(file.filePath);
                    } else {
                      _expanded.add(file.filePath);
                    }
                  });
                },
                isSelected: false,
                expanded: _expanded.contains(file.filePath),
                child: Row(
                  children: [
                    Text(p
                        .basename(file.filePath)
                        .removeSuffix(DrawingFile.fileExtension)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        p.dirname(file.filePath),
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.black38,
                          height: 0.9,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
