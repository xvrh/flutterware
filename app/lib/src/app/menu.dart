import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/app/ui/side_bar.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';

import '../ui.dart';
import 'ui/menu_tree.dart';

class Menu extends StatelessWidget {
  const Menu({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        MenuLine(
          selected: context.router.isSelected('home'),
          onTap: () {
            context.router.go('home');
          },
          type: LineType.expanded,
          depth: 0,
          child: Row(
            children: [
              FlutterLogo(size: 15),
              Expanded(
                child: Text(
                  'flutter_studio_example',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        MenuLine(
          selected: context.router.isSelected('dependencies'),
          onTap: () {
            context.router.go('dependencies');
          },
          type: LineType.leaf,
          depth: 1,
          child: Text('Dependencies'),
        ),
        MenuLine(
          selected: context.router.isSelected('dependencies'),
          onTap: () {},
          onExpand: () {},
          type: LineType.collapsed,
          depth: 1,
          child: Text('Tests'),
        ),
        MenuLine(
          selected: false,
          onTap: () {},
          type: LineType.collapsed,
          depth: 1,
          child: Text('Run on device'),
        ),
      ],
    );
    //return MenuTree(
    //  entries: [
    //    MenuEntry('Home'),
    //    MenuEntry('Dependencies'),
    //    MenuEntry('Tests', children: [
    //      MenuEntry('Onboarding', children: [
    //        MenuEntry('One'),
    //        MenuEntry('Two'),
    //      ]),
    //    ]),
    //    MenuEntry('Run app'),
    //    MenuEntry('Themes'),
    //    MenuEntry('Assets'),
    //    MenuEntry('Animations'),
    //    MenuEntry('Easing'),
    //    MenuEntry('Shaders'),
    //    MenuEntry('Particles'),
    //    MenuEntry('Path'),
    //    MenuEntry('App icon'),
    //    MenuEntry('Benchmarks'),
    //    MenuEntry('Wysiwyg'),
    //    MenuEntry('Icons (GoogleFont, Fontawesome, custom font creation...)'),
    //    MenuEntry('Fonts'),
    //    MenuEntry('Build runner (generic persistent scripts?)'),
    //    MenuEntry('Compilation (mobile, web etc...?)'),
    //  ],
    //  onSelected: (s) {},
    //);
  }
}

enum LineType { leaf, collapsed, expanded }

class MenuLine extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onExpand;
  final LineType type;
  final int depth;
  final Widget child;

  const MenuLine({
    Key? key,
    required this.selected,
    required this.onTap,
    this.onExpand,
    required this.type,
    required this.depth,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.selection : null,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 12.0 * depth),
            GestureDetector(
              onTap: onExpand,
              child: Icon(
                type == LineType.expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 17,
                color: type == LineType.leaf
                    ? Colors.transparent
                    : (selected ? Colors.white : Colors.black54),
              ),
            ),
            const SizedBox(width: 1),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: selected ? Colors.white : null),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
