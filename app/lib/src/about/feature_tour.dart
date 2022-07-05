import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart';

class FeatureTourPage extends StatefulWidget {
  const FeatureTourPage({super.key});

  @override
  State<FeatureTourPage> createState() => _FeatureTourPageState();
}

class _FeatureTourPageState extends State<FeatureTourPage> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Markdown(
        extensionSet: ExtensionSet.gitHubWeb,
        controller: _scrollController,
        data: '''
## Features

### Dependencies overview

A list of all the pub dependencies of a project with some information about each depended package:
- Quality metrics (pub scores, Github stars...)
- Number of imports of this dependency in the project
- Visualize the transitivity path. To understand from where a dependency is coming from.

### App's launcher icon

- View all the launcher icon of the project.
- Allow to update all the icons from a single image.

### App test
 - Run Widget Test in a visual environment with screenshots of each step
 - Configure screen size to common phone format
 - See the app in every supported language
''');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
