import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Card(
        child: Markdown(
          data: '''          
## App test

### Features
##### Screenshot every step of the test

##### Hot Reload to instantaneously see the result

##### Preview all screens in all supported languages

##### Switch to any screen size

##### Enable all accessibility settings

##### Split the test to explore all paths
''',
        ),
      ),
    );
  }
}
