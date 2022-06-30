import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../utils.dart';
import 'theme.dart';

const _menuWidth = 250.0;
const _leftMargin = 20.0;

class SideMenu extends StatelessWidget {
  final List<Widget> children;

  const SideMenu({Key? key, required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _menuWidth,
      child: Material(
        shadowColor: Colors.black,
        elevation: 4,
        color: Colors.white,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 13,
          ),
          child: ListView(
            children: [
              for (var child in children) ...[
                child,
                const Divider(
                  height: 22,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MenuGroup extends StatelessWidget {
  final String title;
  final Widget icon;
  final Map<String, String> links;

  const MenuGroup({
    Key? key,
    required this.title,
    required this.icon,
    required this.links,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var selectedIndex = context.router.selectedIndex(links.keys);
    return ExpansionTile(
      initiallyExpanded: true,
      leading: IconTheme(
        data: IconThemeData(color: Colors.white),
        child: icon,
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: AppColors.menuSecondaryBackground,
      children: links.entries
          .mapIndexed((index, element) => MenuLink(element.key, element.value,
              isSelected: index == selectedIndex))
          .toList(),
    );
  }
}

class MenuLink extends StatelessWidget {
  final String url;
  final String title;
  final bool? isSelected;

  const MenuLink(this.url, this.title, {Key? key, this.isSelected})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var isSelected = this.isSelected ?? context.router.isSelected(url);
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? AppColors.primaryOnMenu : null,
        ),
      ),
      onTap: () {
        context.go(url);
      },
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

class CollapsibleMenu extends StatelessWidget {
  final Widget text;
  final List<Widget>? expanded;

  const CollapsibleMenu({
    super.key,
    required this.text,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    var expanded = this.expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.only(
              left: _leftMargin,
              right: 8,
              top: 3,
              bottom: 3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                    child: text,
                  ),
                ),
                Icon(expanded == null ? Icons.expand_more : Icons.expand_less),
              ],
            ),
          ),
        ),
        ...?expanded,
      ],
    );
  }
}

class LogoTile extends StatelessWidget {
  final String name;
  final String version;

  const LogoTile({super.key, required this.name, required this.version});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
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
                fontSize: 20,
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
      ),
    );
  }
}
