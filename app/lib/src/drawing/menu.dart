import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:more/collection.dart';
import 'package:path/path.dart' as p;
import '../project.dart';
import '../ui/side_menu.dart';
import '../utils.dart';
import 'model/file.dart';

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

  const _ListingMenu(this.project);

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
          children: _lines(files).toList(),
        );
      },
    );
  }

  Iterable<Widget> _lines(Iterable<DrawingFile> files) sync* {
    for (var file in files.sortedByCompare((e) => e.filePath, compareNatural)) {
      var isExpanded = context.router.isSelected(_urlForFile(file));
      yield MenuLine(
        onTap: () {
          context.router.go(_urlForFile(file));
        },
        isSelected: context.router.isSelected(_urlForFile(file)),
        expanded: isExpanded,
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
      );
      if (isExpanded) {
        yield ValueListenableBuilder<List<DrawingEntry>>(
          valueListenable: file.entries,
          builder: (context, entries, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _selectedEntries(file, entries).toList(),
            );
          },
        );
      }
    }
  }

  Iterable<Widget> _selectedEntries(
      DrawingFile file, List<DrawingEntry> entries) sync* {
    for (var entry in entries) {
      var url = _urlForEntry(file, entry);
      yield MenuLine(
        onTap: () {
          context.router.go(url);
        },
        isSelected: context.router.isSelected(url),
        indent: 1,
        child: Row(
          children: [
            Text(entry.name),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                entry.typeName,
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
      );
    }
  }

  String _urlForFile(DrawingFile file) =>
      'drawing/files/${Uri.encodeComponent(file.filePath)}';

  String _urlForEntry(DrawingFile file, DrawingEntry entry) =>
      '${_urlForFile(file)}/${entry.name}';
}
