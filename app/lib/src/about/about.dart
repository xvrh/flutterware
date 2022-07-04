import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ' ABOUT',
            style: theme.textTheme.bodySmall,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: MarkdownBody(
                data: '''
**Flutterware** is a desktop app grouping several tools for [Flutter](https://flutter.dev) development.

This is a hobby project. Any help to improve it is welcome. Open issues, start discussions, submit pull requests… 

- [Github repository](https://github.com/xvrh/flutterware)
- [Pub package](https://pub.dev/packages/flutterware)
''',
                styleSheet: MarkdownStyleSheet(
                  a: const TextStyle(color: AppColors.link),
                ),
                onTapLink: (text, href, title) {
                  if (href != null) {
                    launchUrl(Uri.parse(href));
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
