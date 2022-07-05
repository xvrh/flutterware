import 'package:flutter/material.dart';
import '../utils.dart';
import '../utils/expansion_tile.dart';

const _menuWidth = 250.0;
const _leftMargin = 20.0;

class SideMenu extends StatelessWidget {
  final List<Widget> children;
  final List<Widget>? bottom;

  const SideMenu({Key? key, required this.children, this.bottom})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _menuWidth,
      child: Material(
        shadowColor: Colors.black,
        elevation: 4,
        color: Colors.white,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    for (var child in children) ...[
                      child,
                      Container(height: 1, color: AppColors.primaryBorder),
                    ],
                  ],
                ),
              ),
              ...?bottom,
            ],
          ),
        ),
      ),
    );
  }
}

class MenuLink extends StatefulWidget {
  final String url;
  final Widget title;

  const MenuLink({required this.url, required this.title, Key? key})
      : super(key: key);

  @override
  State<MenuLink> createState() => _MenuLinkState();
}

class _MenuLinkState extends State<MenuLink> {
  bool? _isSelected = false;

  @override
  Widget build(BuildContext context) {
    var isSelected = context.router.isSelected(widget.url);
    if (isSelected != _isSelected) {
      _isSelected = isSelected;
      if (isSelected) {
        var parentMenu = CollapsibleMenu._of(context);
        if (parentMenu != null) {
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
            parentMenu._expansionTileKey.currentState?.expand();
          });
        }
      }
    }

    return MenuLine(
      isSelected: isSelected,
      onTap: () {
        context.go(widget.url);
      },
      child: widget.title,
    );
  }
}

class SingleLineGroup extends StatelessWidget {
  final Widget child;

  const SingleLineGroup({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: child,
    );
  }
}

class MenuLine extends StatelessWidget {
  static const _expandIconWidth = 20.0;

  final Widget child;
  final VoidCallback onTap;
  final bool isSelected;
  final bool? expanded;
  final int indent;

  const MenuLine({
    super.key,
    required this.child,
    required this.onTap,
    required this.isSelected,
    this.expanded,
    int? indent,
  }) : indent = indent ?? 0;

  @override
  Widget build(BuildContext context) {
    var expanded = this.expanded;
    IconData? expandableIcon;
    if (expanded != null) {
      expandableIcon = expanded ? Icons.arrow_drop_down : Icons.arrow_right;
    }

    var borderRadius = BorderRadius.horizontal(right: Radius.circular(20));
    return DefaultTextStyle.merge(
      style: isSelected
          ? TextStyle(
              color: AppColors.navigationForegroundActive,
              fontWeight: FontWeight.w500,
            )
          : null,
      child: IconTheme.merge(
        data: IconThemeData(
          color: isSelected ? AppColors.navigationForegroundActive : null,
          size: 18,
        ),
        child: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: borderRadius,
                    color: AppColors.navigationBackgroundActive,
                  )
                : null,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 3,
                  bottom: 3,
                  left: _leftMargin - _expandIconWidth + indent * 12,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _expandIconWidth,
                      child: Center(
                        child: Icon(expandableIcon),
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CollapsibleMenu extends StatefulWidget {
  final Widget title;
  final List<Widget> children;
  final bool initiallyExpanded;

  const CollapsibleMenu({
    super.key,
    required this.title,
    required this.children,
    bool? initiallyExpanded,
  }) : initiallyExpanded = initiallyExpanded ?? false;

  @override
  State<CollapsibleMenu> createState() => _CollapsibleMenuState();

  static _CollapsibleMenuState? _of(BuildContext context) {
    return context.findAncestorStateOfType<_CollapsibleMenuState>();
  }
}

class _CollapsibleMenuState extends State<CollapsibleMenu> {
  final _expansionTileKey = GlobalKey<ExpansionTileState>();

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        dividerColor: Colors.transparent,
        textTheme: theme.textTheme.copyWith(
          subtitle1: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: ListTileTheme(
        dense: true,
        data: ListTileThemeData(dense: true),
        child: CustomExpansionTile(
          key: _expansionTileKey,
          initiallyExpanded: widget.initiallyExpanded,
          maintainState: true,
          textColor: AppColors.textSecondary,
          collapsedTextColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          title: widget.title,
          children: [...widget.children, const SizedBox(height: 5)],
        ),
      ),
    );
  }
}

class LogoTile extends StatelessWidget {
  final String name;
  final String version;

  const LogoTile({
    super.key,
    required this.name,
    required this.version,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: FlutterLogo(),
          ),
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 10),
            padding: const EdgeInsets.symmetric(
              horizontal: 5,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF01579B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              version,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
              ),
            ),
          )
        ],
      ),
    );
  }
}
