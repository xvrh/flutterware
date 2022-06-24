import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart';

class WarningBox extends StatelessWidget {
  final String message;

  const WarningBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xff856404);
    return Card(
      surfaceTintColor: Color(0xfffff3cd),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(15),
              child: Icon(
                Icons.warning_amber,
                color: foreground,
              ),
            ),
            Expanded(
              child: MarkdownBody(
                data: message,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(color: foreground),
                ),
                extensionSet: ExtensionSet.commonMark,
                inlineSyntaxes: [
                  LineBreakSyntax(),
                ],
                onTapLink: (text, href, title) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
