import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/project_info/image_provider.dart';
import 'package:flutter_studio_app/src/utils/ui/loading.dart';

import '../app/project_view.dart';
import '../project.dart';
import '../utils/async_value.dart';
import '../utils/ui/error_panel.dart';
import '../utils/ui/warning_box.dart';
import 'icons.dart';
import 'package:path/path.dart' as p;

class IconScreen extends StatelessWidget {
  final Project project;

  const IconScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([
      BreadcrumbItem(Text('App icon')),
    ]);
    var theme = Theme.of(context);
    return ValueListenableBuilder<Snapshot<AppIcons>>(
      valueListenable: project.icons.icons,
      builder: (context, snapshot, child) {
        var data = snapshot.data;
        var error = snapshot.error;
        return ListView(
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'App icon',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _changeIcon(context),
                  icon: Icon(Icons.photo),
                  label: Text('Change icon'),
                ),
              ],
            ),
            const SizedBox(height: 30),
            if (data != null)
              ..._icons(context, data)
            else if (error != null)
              ErrorPanel(
                message: 'Failed to load icons',
                onRetry: project.icons.icons.refresh,
              )
            else
              LoadingPanel(),
          ],
        );
      },
    );
  }

  void _changeIcon(BuildContext context) async {
    await showDialog(
        context: context, builder: (context) => _ChangeIconDialog());
    // Pick image
    // Indicate the recommended size
    // Allow to choose image for background on iOS (+ checkbox)
    // Allow to check/uncheck some platforms
    // This is a first version that need to be enhanced.
  }

  Iterable<Widget> _icons(BuildContext context, AppIcons icons) sync* {
    var theme = Theme.of(context);

    for (var entry in icons.icons.entries) {
      if (entry.value.isEmpty) continue;

      yield Text(
        entry.key.name,
        style: theme.textTheme.bodyLarge,
      );
      yield const SizedBox(height: 15);
      yield Table(
        columnWidths: {
          0: FixedColumnWidth(80),
          1: FixedColumnWidth(100),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var icon in entry.value)
            TableRow(
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 50,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                    ),
                    child: Image(
                      image: AppIconImageProvider(icon),
                    ),
                  ),
                ),
                Text(
                  '${icon.originalWidth}x${icon.originalHeight}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  p.relative(icon.path, from: project.directory.path),
                  style: const TextStyle(color: Colors.black45),
                ),
              ],
            ),
        ],
      );
      yield Divider();
      yield const SizedBox(height: 30);
    }
  }
}

class _ChangeIconDialog extends StatefulWidget {
  const _ChangeIconDialog({super.key});

  @override
  State<_ChangeIconDialog> createState() => __ChangeIconDialogState();
}

class __ChangeIconDialogState extends State<_ChangeIconDialog> {
  Uint8List? _image;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change icon'),
      content: SizedBox(
        width: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: () {
                // Load image in memory and display it
              },
              icon: Icon(Icons.file_upload),
              label: Text('Choose icon'),
            ),
            Text('Recommended size: 1024x1024'),
            Row(
              children: [
                Switch(value: true, onChanged: (v) {}),
                Text('Android'),
              ],
            ),
            WarningBox(
              message: 'This feature is limited and experimental.  \n'
                  'If you have suggestions to improve it, [open issues on Github](https://github.com/xvrh/flutter_studio)',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _image != null
              ? () {
                  //TODO: replace all icons with correct size
                  // refresh all icons in service.
                }
              : null,
          child: Text('Apply'),
        ),
      ],
    );
  }
}
