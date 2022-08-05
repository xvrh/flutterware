import 'package:flutter/material.dart';
import 'package:flutterware_app/src/drawing/model/file.dart';

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
        // List files
        // Parse each file and add sub menu with components in the file
        //  (Paths, paints,
        MenuLink(
          url: "drawing/files/xx",
          title: Text('Introduction'),
        ),
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
            for (var file in files)
              MenuLine(
                onTap: () {},
                isSelected: false,
                child: Text(file.filePath),
              ),
          ],
        );
      },
    );
  }
}
