import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ToolbarPosition { top, bottom }

class Toolbar extends StatelessWidget {
  final ToolbarPosition position;
  final List<Widget> items;
  final Widget child;

  const Toolbar(
      {super.key,
      ToolbarPosition? position,
      required this.child,
      required this.items})
      : position = position ?? ToolbarPosition.top;

  @override
  Widget build(BuildContext context) {
    var toolbar = _Toolbar(
      position: position,
      children: items,
    );
    var child = this.child;
    child = MediaQuery.removePadding(
      context: context,
      removeTop: position == ToolbarPosition.top,
      removeBottom: position == ToolbarPosition.bottom,
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        if (position == ToolbarPosition.top) toolbar,
        Expanded(child: child),
        if (position == ToolbarPosition.bottom) toolbar,
      ],
    );
  }
}

const _buttonBackground = Color(0xffeaeaea);
const _textStyle = TextStyle(fontSize: 13, color: Colors.black87);

class _Toolbar extends StatelessWidget {
  final ToolbarPosition position;
  final List<Widget> children;

  const _Toolbar({required this.position, required this.children});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Container(
        color: Colors.white,
        child: SafeArea(
          top: position == ToolbarPosition.top,
          bottom: position == ToolbarPosition.bottom,
          child: Material(
            child: DefaultTextStyle.merge(
              style: _textStyle,
              child: Theme(
                data: _theme(context),
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    children: [
                      for (var child in children) ...[
                        child,
                        if (child != children.last) SizedBox(width: 7),
                      ]
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _theme(BuildContext context) {
    var theme = Theme.of(context);
    return theme.copyWith(
      elevatedButtonTheme: _buttonTheme(),
      iconTheme: theme.iconTheme.merge(_iconTheme()),
    );
  }

  ElevatedButtonThemeData _buttonTheme() {
    return ElevatedButtonThemeData(
      style: ButtonStyle(
        elevation: MaterialStateProperty.all(0),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        ),
        backgroundColor: MaterialStateProperty.all(_buttonBackground),
        foregroundColor: MaterialStateProperty.all(Colors.black87),
        visualDensity: VisualDensity.compact,
        textStyle: MaterialStateProperty.all(_textStyle),
      ),
    );
  }

  IconThemeData _iconTheme() {
    return IconThemeData(size: 20);
  }
}

class ToolbarDropdown<T extends Object> extends StatelessWidget {
  static const _highlightColor = Color(0xff0000ff);

  final T value;
  final void Function(T) onChanged;
  final Map<T, Widget> items;
  final bool showArrow;
  final bool highlight;

  const ToolbarDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.items,
    bool? showArrow,
    bool? highlight,
  })  : showArrow = showArrow ?? true,
        highlight = highlight ?? false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? _highlightColor : _buttonBackground,
        borderRadius: BorderRadius.circular(2),
      ),
      child: DropdownButton<T>(
        value: value,
        items: [
          for (var entry in items.entries)
            DropdownMenuItem(
              value: entry.key,
              child: entry.value,
            ),
        ],
        onChanged: (v) => onChanged(v!),
        icon: Icon(
          Icons.arrow_drop_down,
          color: highlight ? Colors.white : null,
        ),
        iconSize: showArrow ? 18 : 0,
        style: _textStyle.copyWith(color: highlight ? Colors.white : null),
        dropdownColor: highlight ? _highlightColor : null,
        underline: SizedBox(),
      ),
    );
  }
}

class ToolbarPicker<T> extends StatelessWidget {
  final Widget? title;
  final T value;
  final void Function(T) onChanged;
  final Map<T, Widget> items;
  final Map<T, Widget>? itemTiles;

  const ToolbarPicker({
    super.key,
    this.title,
    required this.value,
    required this.onChanged,
    required this.items,
    this.itemTiles,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        showDialog(context: context, builder: _dialog);
      },
      child: items[value] ?? items.values.first,
    );
  }

  Widget _dialog(BuildContext context) {
    return AlertDialog(
      title: title,
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: ListTile.divideTiles(context: context, tiles: [
            for (var item in items.entries) _itemTile(context, item.key),
          ]).toList(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('CANCEL')),
      ],
    );
  }

  Widget _itemTile(BuildContext context, T key) {
    Widget? tile;
    if (itemTiles != null) {
      tile = itemTiles![key];
      if (tile != null) {
        tile = InkWell(
          onTap: () => _onTap(context, key),
          child: tile,
        );
      }
    }
    tile ??= ListTile(
      title: items[key],
      onTap: () => _onTap(context, key),
    );

    tile = Row(children: [
      Expanded(child: tile),
      Icon(key == value ? Icons.check : null, color: Color(0xff0000ff)),
    ]);

    return tile;
  }

  void _onTap(BuildContext context, T key) {
    onChanged(key);
    Navigator.pop(context);
  }
}
