import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/app/ui/side_bar.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';

import '../project.dart';
import '../ui.dart';
import '../utils/data_loader.dart';
import 'ui/menu_tree.dart';
import 'paths.dart' as paths;

class Menu extends StatefulWidget {
  final Project project;

  const Menu(this.project, {super.key});

  @override
  State<Menu> createState() => _MenuState();
}

class _MenuState extends State<Menu> {
  final _expanded = <String>{};

  void _toggle(String path) {
    setState(() {
      if (_expanded.contains(path)) {
        _expanded.remove(path);
      } else {
        _expanded.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Snapshot<Pubspec>>(
        valueListenable: widget.project.pubspec,
        builder: (context, snapshot, child) {
          return ListView(
            children: [
              MenuLine(
                selected: context.router.isSelected(paths.home),
                onTap: () {
                  context.router.go(paths.home);
                },
                type: LineType.expanded,
                depth: 0,
                child: Row(
                  children: [
                    FlutterLogo(size: 15),
                    Expanded(
                      child: Text(
                        snapshot.data?.name ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              MenuLine(
                selected: context.router.isSelected(paths.dependencies),
                onTap: () {
                  context.router.go(paths.dependencies);
                },
                type: LineType.leaf,
                depth: 1,
                child: Text('Dependencies'),
              ),
              MenuLine(
                selected: context.router.selection(paths.tests) ==
                    SelectionType.selected,
                onTap: () {
                  context.router.go(paths.tests);
                  setState(() {
                    _expanded.add(paths.tests);
                  });
                },
                onExpand: () => _toggle(paths.tests),
                type: _expanded.contains(paths.tests)
                    ? LineType.expanded
                    : LineType.collapsed,
                depth: 1,
                child: Row(
                  children: [
                    Expanded(child: Text('Tests')),
                    IconButton(
                      onPressed: () {},
                      constraints: BoxConstraints(),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.info_outline,
                        size: 18,
                      ),
                    )
                  ],
                ),
              ),
              if (_expanded.contains(paths.tests)) ...[
                MenuLine(
                  selected: false,
                  onTap: () {},
                  type: LineType.collapsed,
                  depth: 2,
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder,
                        size: 16,
                        color: Color(0xff8cd3ec),
                      ),
                      const SizedBox(width: 4),
                      Expanded(child: Text('onboarding_test.dart')),
                    ],
                  ),
                ),
                MenuLine(
                  selected: false,
                  onTap: () {},
                  type: LineType.collapsed,
                  depth: 2,
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder,
                        size: 16,
                        color: Color(0xff8cd3ec),
                      ),
                      const SizedBox(width: 4),
                      Expanded(child: Text('app_test.dart')),
                    ],
                  ),
                ),
              ],
              MenuLine(
                selected: false,
                onTap: () {},
                type: LineType.collapsed,
                depth: 1,
                child: Text('Run on device'),
              ),
              MenuLine(
                selected: false,
                onTap: () {},
                type: LineType.collapsed,
                depth: 1,
                child: Text('Themes'),
              ),
            ],
          );
        });
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
    //    MenuEntry('Lottie animations'),
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
