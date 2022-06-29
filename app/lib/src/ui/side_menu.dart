import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../utils.dart';
import 'theme.dart';

const _menuWidth = 250.0;

class SideMenu extends StatelessWidget {
  final List<Widget> children;

  const SideMenu({Key? key, required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(),
      child: Builder(builder: (context) {
        return SizedBox(
          width: _menuWidth,
          child: Material(
            shadowColor: Colors.black,
            elevation: 4,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
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
                          'Flutterware',
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
                            'v0.1.0',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.horizontal(right: Radius.circular(20)),
                    //highlightShape: RoundedRectangleBorder(),
                    onTap: () {
                      context.go('/');
                    },
                    child: _Logo(),
                  ),
                ),
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        );
      }),
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
            Icons.home,
            //color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            'my_project_name',
            style: const TextStyle(
              //fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
