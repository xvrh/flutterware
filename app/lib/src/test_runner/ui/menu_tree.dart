import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

import '../../ui/side_menu.dart';
import '../../utils.dart';

class MenuTree extends StatefulWidget {
  final List<MenuEntry> entries;
  final TreePath? selected;
  final void Function(TreePath) onSelected;
  final int extraDepth;

  const MenuTree({
    Key? key,
    required this.entries,
    this.selected,
    required this.onSelected,
    int? extraDepth,
  })  : extraDepth = extraDepth ?? 0,
        super(key: key);

  @override
  State<MenuTree> createState() => _MenuTreeState();
}

class _MenuTreeState extends State<MenuTree> {
  final _expanded = <TreePath>[];
  final _allLines = <_Line>[];
  final _visibleLines = <_Line>[];

  @override
  void initState() {
    super.initState();
    _refresh();
    _ensureSelected();
  }

  @override
  void didUpdateWidget(covariant MenuTree oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.entries != oldWidget.entries) {
      _refresh();
    }

    if (oldWidget.selected != widget.selected) {
      _ensureSelected();
    }
  }

  void _refresh() {
    _allLines.clear();
    _visibleLines.clear();
    _fill(widget.entries, const []);
    for (var line in _allLines) {
      if (line.path.isRoot || line.path.isExpanded(_expanded)) {
        _visibleLines.add(line);
      }
    }
  }

  void _fill(List<MenuEntry> entries, List<String> path) {
    for (var entry in entries) {
      var children = entry.children;
      var isLeaf = children == null || children.isEmpty;
      var newPath = [...path, entry.text];
      _allLines.add(_Line(
        TreePath(newPath),
        isLeaf: isLeaf,
        entry: entry,
      ));
      if (children != null) {
        _fill(children, newPath);
      }
    }
  }

  void _ensureSelected() {
    var selected = widget.selected;
    if (selected != null) {
      var changed = false;
      for (var line in _allLines) {
        var path = line.path;
        if (!line.isLeaf &&
            selected.startsWith(path) &&
            !_expanded.contains(path)) {
          changed = true;
          _expanded.add(path);
        }
      }
      if (changed) {
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var line in _visibleLines)
          MenuLine(
            expanded: line.isLeaf ? null : _expanded.contains(line.path),
            isSelected: widget.selected == line.path,
            indent: line.depth + widget.extraDepth,
            onTap: () {
              if (!line.isLeaf) {
                setState(() {
                  if (_expanded.contains(line.path)) {
                    _expanded.remove(line.path);
                  } else {
                    _expanded.add(line.path);
                  }
                  _refresh();
                });
              } else {
                widget.onSelected(line.path);
              }
            },
            child: Text(line.entry.text),
          ),
      ],
    );
  }
}

/*
class _LineView extends StatelessWidget {
  final _Line line;
  final bool expanded;
  final VoidCallback onTap;
  final bool selected;
  final int extraDepth;

  const _LineView(
    this.line, {
    Key? key,
    required this.expanded,
    required this.onTap,
    required this.selected,
    required this.extraDepth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.link : null,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 12.0 * (line.depth + extraDepth)),
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: 17,
              color: line.isLeaf ? Colors.transparent : Colors.black54,
            ),
            const SizedBox(width: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Icon(
                line.isLeaf ? Icons.insert_drive_file : Icons.folder,
                size: 16,
                color: line.isLeaf ? AppColors.link : Color(0xff8cd3ec),
              ),
            ),
            Expanded(
              child: Text(
                line.entry.text,
                style: TextStyle(color: selected ? Colors.white : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
*/
class MenuEntry {
  final List<MenuEntry>? children;
  final String text;

  MenuEntry(this.text, {this.children});
}

class _Line {
  final TreePath path;
  final bool isLeaf;
  final MenuEntry entry;

  _Line(
    this.path, {
    required this.isLeaf,
    required this.entry,
  });

  int get depth => path.nodes.length - 1;

  @override
  String toString() => '_Line($path)';
}

class TreePath {
  final List<String> nodes;

  TreePath(this.nodes) : assert(nodes.isNotEmpty);

  factory TreePath.fromEncoded(String path) {
    return TreePath(
        path.split('/').map((n) => Uri.decodeComponent(n)).toList());
  }

  bool get isRoot => nodes.length == 1;

  bool startsWith(TreePath path) {
    if (path.nodes.length > nodes.length) return false;

    for (var i = 0; i < path.nodes.length; i++) {
      if (path.nodes[i] != nodes[i]) return false;
    }
    return true;
  }

  bool isExpanded(List<TreePath> expanded) {
    var parent = basePath;
    while (parent != null) {
      if (!expanded.contains(parent)) return false;
      parent = parent.basePath;
    }
    return true;
  }

  TreePath? get basePath =>
      isRoot ? null : TreePath(nodes.take(nodes.length - 1).toList());

  String get encoded => nodes.map((n) => Uri.encodeComponent(n)).join('/');

  @override
  bool operator ==(other) =>
      other is TreePath && const ListEquality().equals(nodes, other.nodes);

  @override
  int get hashCode => const ListEquality().hash(nodes);

  @override
  String toString() => nodes.join('/');
}
