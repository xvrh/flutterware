import 'package:flutter/material.dart';
import 'package:flutterware/src/ui_book/figma/link.dart';
import 'package:flutterware/src/ui_book/figma/provider.dart';
import 'package:flutterware/src/ui_book/figma/ui/column.dart';
import 'package:flutterware/src/ui_book/figma/ui/settings.dart';

import '../../utils/value_stream.dart';
import '../app.dart';
import 'ui/clipboard_button.dart';
import 'ui/info_dialog.dart';

class FigmaView extends StatelessWidget {
  final TreeEntry entry;
  final Widget child;
  final double Function() floatDefaultWidth;

  FigmaView({
    super.key,
    required this.child,
    required this.entry, required this.floatDefaultWidth,
  });

  @override
  Widget build(BuildContext context) {
    var figmaService = FigmaProvider.of(context).service;
    var path = entry.path;
    return ValueStreamBuilder<List<FigmaLink>>(
      stream: figmaService.linksForPath(path),
      builder: (context, snapshot) {
        return FigmaPreviewer(
          figmaService,
          key: ValueKey(entry),
          onOpenSettings: figmaService.canSaveFigmaToken
              ? () {
                  showFigmaSettingsDialog(context, figmaService);
                }
              : null,
          figmaLinks: snapshot,
          onAddLink: (v) {
            figmaService.addLink(path, v);
          },
          onLinkSettings: (link) {
            showFigmaLinkDialog(context, figmaService, entry, link);
          },
          clipboardButton: ClipboardButton(figmaService, entry),
          floatDefaultWidth: floatDefaultWidth,
          child: child,
        );
      },
    );
  }
}
