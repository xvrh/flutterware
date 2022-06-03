

import 'package:flutter/material.dart';
import '../app/ui/menu.dart';
import '../project.dart';

class TestMenuLine extends StatelessWidget {
  final Project project;

  const TestMenuLine(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}

class TestMenu extends StatelessWidget {

  final Project project;

  const TestMenu(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      ...[
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
      ]
    ],);
  }
}
