import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../utils.dart';
import 'theme.dart';

class SideMenu extends StatelessWidget {
  final List<Widget> children;

  const SideMenu({Key? key, required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: darkTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: Colors.white),
        child: Builder(builder: (context) {
          return SizedBox(
            width: 200,
            child: Material(
              color: AppColors.menuBackground,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () {
                      context.go('/');
                    },
                    child: _Logo(),
                  ),
                  const SizedBox(height: 10),
                  ...children,
                ],
              ),
            ),
          );
        }),
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

class _Logo extends StatelessWidget {
  const _Logo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Icon(
            Icons.developer_board,
            color: Color(0xfff8cb51),
          ),
          const SizedBox(width: 10),
          Text(
            'Dev Console',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
