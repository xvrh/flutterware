import 'package:flutter/material.dart';
import '../third_party/device_frame/lib/device_frame.dart';
import 'app.dart';
import 'treeview.dart';

class IndexView extends StatelessWidget {
  final List<TreeEntry> children;
  final void Function(TreeEntry) onSelect;
  final bool isRoot;

  const IndexView(
    this.children, {
    super.key,
    required this.onSelect,
    required this.isRoot,
  });

  @override
  Widget build(BuildContext context) {
    var leafs = children.where((e) => e.isLeaf);
    var folders = children.where((e) => !e.isLeaf);

    var widgets = <Widget>[
      GridView.count(
        padding: const EdgeInsets.all(20),
        crossAxisCount: 5,
        mainAxisSpacing: 30,
        crossAxisSpacing: 30,
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        children: [
          for (var child in leafs)
            _IndexPreview(
              child,
              child.value,
              onTap: () {
                onSelect(child);
              },
            )
        ],
      ),
      for (var folder in folders)
        _Folder(
          title: folder.title,
          onSelect: () => onSelect(folder),
          child: IndexView(folder.children!, onSelect: onSelect, isRoot: false),
        )
    ];

    if (isRoot) {
      return ListView(
        children: widgets,
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: widgets,
      );
    }
  }
}

class _IndexPreview extends StatelessWidget {
  final TreeEntry entry;
  final dynamic value;
  final VoidCallback onTap;

  _IndexPreview(this.entry, this.value, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    var value = this.value;
    Widget mainWidget;
    if (value is Widget) {
      var widget = Center(
        child: value,
      );
      mainWidget = DeviceFrame(
        device: Devices.android.smallPhone,
        screen: widget,
        isFrameVisible: false,
      );
    } else {
      mainWidget = Center(
        child: Text('Entry is not a widget. Type: ${value.runtimeType}'),
      );
    }
    return InkWell(
      onTap: onTap,
      focusColor: Colors.transparent,
      child: AbsorbPointer(
        child: AspectRatio(
          aspectRatio: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  constraints: BoxConstraints(maxHeight: 200, maxWidth: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black12, width: 1),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: mainWidget,
                    ),
                  ),
                ),
              ),
              Text(
                entry.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Folder extends StatelessWidget {
  final Widget child;
  final String title;
  final VoidCallback onSelect;

  const _Folder({
    required this.title,
    required this.child,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 30, left: 20, right: 20),
      decoration: BoxDecoration(
        color: folderColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: folderColor.withOpacity(0.5), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onSelect,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
