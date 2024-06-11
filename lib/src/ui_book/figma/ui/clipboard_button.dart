import 'package:flutter/material.dart';
import 'package:flutterware/src/ui_book/app.dart';
import 'package:flutterware/src/ui_book/figma/service.dart';
import 'package:flutterware/src/utils/value_stream.dart';

class ClipboardButton extends StatelessWidget {
  final FigmaService service;
  final TreeEntry entry;

  const ClipboardButton(this.service, this.entry, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueStreamBuilder(
      stream: service.clipboardWatcher.proposedLink,
      builder: (context, link) {
        if (link == null) {
          return const SizedBox();
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: IconButton(
              onPressed: () {
                service.addLink(entry.path, link);
              },
              tooltip: 'Add from clipboard',
              icon: Icon(Icons.paste),
            ),
          );
        }
      },
    );
  }
}
