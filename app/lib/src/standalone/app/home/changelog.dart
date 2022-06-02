import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChangeLogTab extends StatelessWidget {
  const ChangeLogTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Markdown(data: '''
## Changelog

#### v0.1.0
- `test_ui` feature: A GUI built on top of the “flutter test” framework.
''');
  }
}