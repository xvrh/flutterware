import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/app/ui/side_bar.dart';

import '../ui.dart';
import 'ui/menu_tree.dart';

class Menu extends StatelessWidget {
  const Menu({super.key});

  @override
  Widget build(BuildContext context) {
    return MenuTree(
      entries: [
        MenuEntry('Home'),
        MenuEntry('Dependencies'),
        MenuEntry('Tests', children: [
          MenuEntry('Onboarding', children: [
            MenuEntry('One'),
            MenuEntry('Two'),
          ]),
        ]),
        MenuEntry('Run app'),
        MenuEntry('Themes'),
        MenuEntry('Assets'),
        MenuEntry('Animations'),
        MenuEntry('Easing'),
        MenuEntry('Shaders'),
        MenuEntry('Particles'),
        MenuEntry('Path'),
        MenuEntry('App icon'),
        MenuEntry('Benchmarks'),
        MenuEntry('Wysiwyg'),
      ],
      onSelected: (s) {},
    );
  }
}

enum LineType { none, collapsed, expanded }

class MenuLine extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final LineType type;
  final int depth;
  final Widget child;

  const MenuLine({
    Key? key,
    required this.selected,
    required this.onTap,
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
            Icon(
              type == LineType.expanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 17,
              color:
                  type == LineType.none ? Colors.transparent : Colors.black54,
            ),
            const SizedBox(width: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
