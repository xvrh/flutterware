import 'dart:core' as core;
import 'dart:core';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'detail.dart';
import 'index.dart';
import 'treeview.dart';
import 'widget_book.dart';

const _menuBackground = Color(0xfff7f9fc);

class WidgetBook extends StatefulWidget {
  final String title;
  final Map<String, dynamic> Function() books;
  final Widget Function(BuildContext, Widget) appBuilder;

  const WidgetBook({
    super.key,
    required this.title,
    required this.books,
    required this.appBuilder,
  });

  @override
  State<WidgetBook> createState() => WidgetBookAppState();

  static WidgetBook of(BuildContext context) =>
      context.findAncestorWidgetOfExactType<WidgetBook>()!;
}

class WidgetBookAppState extends State<WidgetBook> {
  final topBarPickers = <String, PickerState>{};
  String? _selected;

  @override
  Widget build(BuildContext context) {
    var allBooks = widget.books();
    var entries = _mapToEntries(allBooks);
    TreeEntry? selected;
    if (_selected case var selectedPath?) {
      selected =
          _flatEntries(entries).firstWhereOrNull((e) => e.path == selectedPath);
    } else {
      selected = TreeEntry(null, MapEntry('', allBooks));
    }
    return MaterialApp(
      color: Colors.red,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 200,
              decoration: BoxDecoration(
                color: _menuBackground,
                border: Border(
                  right: BorderSide(color: Color(0xffe4e5e8), width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 15, top: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selected = null;
                              });
                            },
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        _SettingsButton(),
                      ],
                    ),
                  ),
                  _SearchField(),
                  Expanded(
                    child: TreeView<TreeEntry>(
                      entries: entries,
                      onSelected: (e) {
                        setState(() {
                          _selected = e.path;
                        });
                      },
                      selected: selected,
                      adapter: TreeEntryAdapter(
                        children: (e) => e.children,
                        title: (e) => e.title,
                        ancestors: (e) => e.parent?.breadcrumb ?? [],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: selected == null ? SizedBox() : _detailOrListing(selected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailOrListing(TreeEntry entry) {
    var value = entry.value;
    if (value != null) {
      return DetailView(
        entry,
        value,
        onSelect: (e) {
          setState(() {
            _selected = e.path;
          });
        },
        appState: this,
        key: Key(entry.path),
      );
    } else {
      var scaffold = Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 20,
                top: 10,
              ),
              child: entry.isRoot
                  ? Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Breadcrumb(entry, onSelect: (e) {
                      setState(() {
                        _selected = e.path;
                      });
                    }),
            ),
            Expanded(
              child: IndexView(
                isRoot: true,
                entry.children ?? [],
                onSelect: (e) {
                  setState(() {
                    print('Select ${e.path}');
                    _selected = e.path;
                  });
                },
              ),
            ),
          ],
        ),
      );
      return WidgetBookStateProvider(
        state: WidgetBookState.empty,
        child: Builder(builder: (context) {
          return widget.appBuilder(
            context,
            scaffold,
          );
        }),
      );
    }
  }

  static List<TreeEntry> _mapToEntries(Map<String, dynamic> map) {
    return map.entries.map((e) => TreeEntry(null, e)).toList();
  }

  static Iterable<TreeEntry> _flatEntries(List<TreeEntry> roots) sync* {
    for (var root in roots) {
      yield root;
      yield* root.descendants;
    }
  }
}

class _SettingsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton(
      icon: Icon(
        Icons.settings_outlined,
        color: Colors.black38,
      ),
      iconSize: 15,
      itemBuilder: (c) => [
        PopupMenuItem(
          child: Text('Some option'),
        )
      ],
    );
  }
}

class _SearchField extends StatefulWidget {
  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: TextField(
        controller: _textController,
        decoration: InputDecoration(
          hintText: 'Filter',
          prefixIcon: Icon(Icons.search),
          prefixIconConstraints: BoxConstraints(minHeight: 40, minWidth: 40),
          suffixIconConstraints: BoxConstraints(minHeight: 40),
          suffixIcon: _textController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      _textController.clear();
                    });
                    FocusScope.of(context).unfocus();
                  },
                  icon: Icon(Icons.clear))
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onChanged: (v) {
          setState(() {
            // Update suffix
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}

class TreeEntry {
  final TreeEntry? parent;
  final MapEntry<String, dynamic> entry;
  late final List<TreeEntry> breadcrumb = <TreeEntry>[
    ...?parent?.breadcrumb,
    this
  ];

  TreeEntry(this.parent, this.entry);

  bool get isRoot => entry.key.isEmpty;

  String get title => entry.key;

  String get path => breadcrumb
      .where((e) => e.entry.key.isNotEmpty)
      .map((e) => e.entry.key)
      .join('/');

  Object? get value {
    var mapValue = entry.value;
    if (mapValue is Map) {
      return null;
    }
    return mapValue;
  }

  bool get isLeaf => entry.value is! Map;

  List<TreeEntry>? get children {
    var mapValue = entry.value;
    if (mapValue is Map<String, dynamic>) {
      return mapValue.entries.map((e) => TreeEntry(this, e)).toList();
    }
    assert(mapValue is! Map);
    return null;
  }

  Iterable<TreeEntry> get descendants sync* {
    if (children == null) return;
    for (var child in children!) {
      yield child;
      yield* child.descendants;
    }
  }

  @override
  bool operator ==(other) => other is TreeEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
