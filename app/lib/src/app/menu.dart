import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/test_runner/menu.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';

import '../project.dart';
import '../utils/data_loader.dart';
import 'ui/menu.dart';
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
                child: ValueListenableBuilder<Snapshot<Pubspec>>(
                  valueListenable: widget.project.pubspec,
                  builder: (context, snapshot, child) {
                    return Text(
                      snapshot.data?.name ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    );
                  },
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
          selected:
              context.router.selection(paths.tests) == SelectionType.selected,
          onTap: () {
            context.router.go(paths.tests);
            setState(() {
              _expanded.add(paths.tests);
            });
          },
          onExpand: widget.project.tests.isStarted
              ? () {
                  _toggle(paths.tests);
                }
              : null,
          type: _expanded.contains(paths.tests)
              ? LineType.expanded
              : LineType.collapsed,
          depth: 1,
          child: Text('Tests'),
        ),
        if (_expanded.contains(paths.tests)) TestMenu(widget.project),
        MenuLine(
          selected: context.router.isSelected(paths.runs),
          onTap: () {
            context.router.go(paths.runs);
          },
          type: LineType.leaf,
          depth: 1,
          child: Text('Run on device'),
        ),
        MenuLine(
          selected:
              context.router.selection(paths.themes) == SelectionType.selected,
          onTap: () {
            context.router.go(paths.themes);
          },
          type: LineType.collapsed,
          depth: 1,
          child: Text('Themes'),
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
