import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/app/ui/menu_tree.dart';
import 'package:flutter_studio_app/src/utils/debug.dart';

void main() => runDebugApp(MenuTreeExample());

class MenuTreeExample extends StatefulWidget {
  const MenuTreeExample({Key? key}) : super(key: key);

  @override
  State<MenuTreeExample> createState() => _MenuTreeExampleState();
}

class _MenuTreeExampleState extends State<MenuTreeExample> {
  TreePath? _menu1Selected = TreePath(['Sign up', 'Legal terms']);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 200,
              child: MenuTree(
                selected: _menu1Selected,
                onSelected: (s) {
                  setState(() {
                    _menu1Selected = s;
                  });
                },
                entries: [
                  MenuEntry('Onboarding'),
                  MenuEntry('Sign in'),
                  MenuEntry('Sign up', children: [
                    MenuEntry('Create account'),
                    MenuEntry('Legal terms'),
                    MenuEntry('Second level', children: [
                      MenuEntry('Third level'),
                    ]),
                  ]),
                  MenuEntry('Robot', children: [
                    MenuEntry('Add'),
                    MenuEntry('Delete'),
                    MenuEntry('Setup wifi'),
                  ]),
                ],
              ),
            ),
            VerticalDivider(),
            /*SizedBox(
              width: 200,
              child: MenuTree(
                selected: _menu1Selected,
                onSelected: (s) {},
                entries: [
                  MenuEntry('Onboarding'),
                  MenuEntry('Sign in'),
                  MenuEntry('Sign up', children: [
                    MenuEntry('Create account'),
                    MenuEntry('Legal terms'),
                  ]),
                  MenuEntry('Robot', children: [
                    MenuEntry('Add'),
                    MenuEntry('Delete'),
                    MenuEntry('Setup wifi'),
                  ]),
                ],
              ),
            ),
            VerticalDivider(),*/
          ],
        ),
      ),
    );
  }
}
