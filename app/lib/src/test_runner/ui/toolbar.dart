import 'package:flutter/material.dart';

class Toolbar extends StatelessWidget {
  final List<Widget> children;

  const Toolbar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme(context),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: Row(
            children: [
              if (children.isNotEmpty)
                for (var child in children) ...[
                  child,
                  if (child != children.last) const SizedBox(width: 7),
                ],
            ],
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
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
              side: BorderSide(color: _buttonBorderColor)),
        ),
        backgroundColor: WidgetStateProperty.all(_buttonBackground),
        foregroundColor: WidgetStateProperty.all(Colors.black87),
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(_textStyle),
      ),
    );
  }

  IconThemeData _iconTheme() {
    return IconThemeData(size: 20);
  }
}

const _buttonBackground = Colors.white;
const _buttonBorderColor = Color(0xffC4C4C4);
const _textStyle = TextStyle(fontSize: 13, color: Colors.black87);

class ToolbarDropdown<T extends Object> extends StatelessWidget {
  static const _highlightColor = Color(0xff0000ff);

  final T? value;
  final void Function(T) onChanged;
  final Map<T, Widget> items;
  final bool showArrow;
  final bool highlight;
  final Widget? hint;

  const ToolbarDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.items,
    bool? showArrow,
    bool? highlight,
    this.hint,
  })  : showArrow = showArrow ?? true,
        highlight = highlight ?? false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? _highlightColor : _buttonBackground,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _buttonBorderColor, width: 1),
      ),
      child: DropdownButton<T>(
        value: value,
        isExpanded: false,
        hint: hint,
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
          child: Text('CANCEL'),
        ),
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

class ToolbarPanel extends StatefulWidget {
  final Widget button;
  final Widget panel;

  const ToolbarPanel({super.key, required this.button, required this.panel});

  @override
  State<ToolbarPanel> createState() => ToolbarPanelState();

  static ToolbarPanelState of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ToolbarPanelProvider>()!
        .panel;
  }
}

class ToolbarPanelState extends State<ToolbarPanel> {
  final LayerLink layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void showMenu() {
    hideMenu();
    var overlay = _overlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return _ToolbarPanelProvider(
          panel: this,
          child: Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: hideMenu,
              child: _Menu(
                link: layerLink,
                child: widget.panel,
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(overlay);
  }

  void hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        showMenu();
      },
      child: CompositedTransformTarget(
        link: layerLink,
        child: widget.button,
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final LayerLink link;
  final Widget child;

  const _Menu({
    required this.link,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: link,
        offset: Offset(-20, 22),
        child: Card(
          color: theme.canvasColor,
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ToolbarPanelProvider extends InheritedWidget {
  final ToolbarPanelState panel;
  const _ToolbarPanelProvider({
    required super.child,
    required this.panel,
  });

  @override
  bool updateShouldNotify(_ToolbarPanelProvider oldWidget) {
    return true;
  }
}
