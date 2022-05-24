import 'package:flutter/material.dart';

class ProjectTabs extends StatelessWidget {
  const ProjectTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _Tab(),
        _Tab(),
        _Tab(),
        IconButton(onPressed: () {}, icon: Icon(Icons.add)),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text('Bla'),
    );
  }
}
