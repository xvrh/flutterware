import 'dart:async';
import 'package:flutter/material.dart';

const _buttonBackground = Color(0xffeaeaea);
const _textStyle = TextStyle(fontSize: 13, color: Colors.black87);

class Toolbar extends StatelessWidget {
  static const height = 40.0;

  final List<Widget> children;

  const Toolbar({Key? key, required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      child: DefaultTextStyle.merge(
        style: _textStyle,
        child: Theme(
          data: _theme(context),
          child: SizedBox(
            height: height,
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

class ToolbarDropdown<T> extends StatelessWidget {
  static const _highlightColor = Color(0xff0000ff);

  final T value;
  final void Function(T?) onChanged;
  final Map<T, Widget> items;
  final bool showArrow;
  final bool highlight;

  const ToolbarDropdown({
    Key? key,
    required this.value,
    required this.onChanged,
    required this.items,
    bool? showArrow,
    bool? highlight,
  })  : showArrow = showArrow ?? true,
        highlight = highlight ?? false,
        super(key: key);

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
        onChanged: (v) => onChanged(v),
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
    Key? key,
    this.title,
    required this.value,
    required this.onChanged,
    required this.items,
    this.itemTiles,
  }) : super(key: key);

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

class ToolbarCheckbox extends StatelessWidget {
  final String title;
  final bool value;
  final void Function(bool) onChanged;

  const ToolbarCheckbox({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        onChanged(!value);
      },
      child: Row(
        children: [
          Center(child: Text(title)),
          Checkbox(value: value, onChanged: (v) => onChanged(v!)),
        ],
      ),
    );
  }
}

class ToolbarPanel extends StatefulWidget {
  final Widget button;
  final Widget panel;

  const ToolbarPanel({Key? key, required this.button, required this.panel})
      : super(key: key);

  @override
  State<ToolbarPanel> createState() => ToolbarPanelState();

  static ToolbarPanelState of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ToolbarPanelProvider>()!
        .panel;
  }
}

class ToolbarPanelState extends State<ToolbarPanel> {
  final _refreshStream = StreamController.broadcast();
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
                panelState: this,
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
    _refreshStream.add(null);
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

  @override
  void dispose() {
    _refreshStream.close();
    super.dispose();
  }
}

class _Menu extends StatelessWidget {
  final LayerLink link;
  final ToolbarPanelState panelState;

  const _Menu({
    Key? key,
    required this.link,
    required this.panelState,
  }) : super(key: key);

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
            child: StreamBuilder<void>(
              stream: panelState._refreshStream.stream,
              builder: (context, snapshot) {
                return panelState.widget.panel;
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarPanelProvider extends InheritedWidget {
  final ToolbarPanelState panel;
  const _ToolbarPanelProvider({
    Key? key,
    required Widget child,
    required this.panel,
  }) : super(key: key, child: child);

  @override
  bool updateShouldNotify(_ToolbarPanelProvider oldWidget) {
    return true;
  }
}
